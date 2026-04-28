<?php

namespace App\Services\Admin;

use App\Models\Admin;
use App\Models\Parking;
use App\Models\ParkingOwner;
use App\Models\Payment;
use App\Models\Reservation;
use App\Models\User;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Support\Collection;

class UserManagementService
{
    public function listUsers(): Collection
    {
        $admins = Admin::query()
            ->orderByDesc('updated_at')
            ->get()
            ->map(fn (Admin $admin): array => $this->toUserRow($admin, 'ADMIN'));

        $owners = ParkingOwner::query()
            ->orderByDesc('updated_at')
            ->get()
            ->map(fn (ParkingOwner $owner): array => $this->toUserRow($owner, 'OWNER'));

        $clients = User::query()
            ->orderByDesc('updated_at')
            ->get()
            ->map(fn (User $client): array => $this->toUserRow($client, 'CLIENT'));

        return $admins
            ->concat($owners)
            ->concat($clients)
            ->sortByDesc('lastActiveTimestamp')
            ->values()
            ->map(fn (array $row): array => collect($row)->except('lastActiveTimestamp')->all());
    }

    public function summarizeUsers(Collection $users): array
    {
        return [
            'all' => $users->count(),
            'admins' => $users->where('roleKey', 'ADMIN')->count(),
            'owners' => $users->where('roleKey', 'OWNER')->count(),
            'clients' => $users->where('roleKey', 'CLIENT')->count(),
            'ownersActive' => $users
                ->where('roleKey', 'OWNER')
                ->where('accountStatus', 'active')
                ->count(),
            'ownersBlocked' => $users
                ->where('roleKey', 'OWNER')
                ->where('accountStatus', 'blocked')
                ->count(),
        ];
    }

    public function setOwnerAccountStatus(
        string $ownerId,
        string $accountStatus,
        ?string $subscriptionStatus = null,
        ?string $reason = null
    ): ?ParkingOwner {
        /** @var ParkingOwner|null $owner */
        $owner = ParkingOwner::query()->find($ownerId);

        if (! $owner) {
            return null;
        }

        $normalizedAccountStatus = strtolower($accountStatus) === 'blocked' ? 'blocked' : 'active';
        $normalizedSubscriptionStatus = strtolower((string) ($subscriptionStatus ?? ''));

        $owner->account_status = $normalizedAccountStatus;

        if (in_array($normalizedSubscriptionStatus, ['active', 'expired', 'paused'], true)) {
            $owner->subscription_status = $normalizedSubscriptionStatus;
        } elseif ($normalizedAccountStatus === 'blocked') {
            $owner->subscription_status = 'expired';
        } elseif (! $owner->subscription_status) {
            $owner->subscription_status = 'active';
        }

        if ($normalizedAccountStatus === 'blocked') {
            $owner->blocked_at = now();
            $owner->blocked_reason = $reason ? trim($reason) : 'Subscription not active';
        } else {
            $owner->blocked_at = null;
            $owner->blocked_reason = null;
        }

        $owner->save();

        /** @var ParkingOwner $fresh */
        $fresh = $owner->fresh() ?? $owner;

        return $fresh;
    }

    public function toOwnerUserRow(ParkingOwner $owner): array
    {
        return collect($this->toUserRow($owner, 'OWNER'))
            ->except('lastActiveTimestamp')
            ->all();
    }

    public function listGlobalHistory(int $limit = 120): Collection
    {
        $safeLimit = max(20, min($limit, 300));
        $perSource = max(20, min($safeLimit, 150));

        $events = collect()
            ->concat($this->accountEvents($perSource))
            ->concat($this->parkingEvents($perSource))
            ->concat($this->reservationEvents($perSource))
            ->concat($this->paymentEvents($perSource));

        return $events
            ->sortByDesc('occurredAtTimestamp')
            ->take($safeLimit)
            ->values()
            ->map(fn (array $event): array => collect($event)->except('occurredAtTimestamp')->all());
    }

    private function toUserRow(object $actor, string $roleKey): array
    {
        $normalizedRole = strtoupper($roleKey);
        $accountStatus = $this->normalizeAccountStatus($normalizedRole === 'OWNER'
            ? (string) ($actor->account_status ?? 'active')
            : 'active');

        $statusLabel = $normalizedRole === 'OWNER'
            ? ($accountStatus === 'blocked' ? 'Suspendu' : 'Actif')
            : 'Actif';

        $statusTone = $normalizedRole === 'OWNER'
            ? ($accountStatus === 'blocked' ? 'danger' : 'success')
            : 'success';

        $lastActiveAt = $this->toIso8601(
            $actor->last_login_at
                ?? $actor->updated_at
                ?? $actor->created_at
                ?? null
        );

        return [
            'id' => (string) $actor->getKey(),
            'name' => (string) ($actor->name ?? ''),
            'email' => strtolower((string) ($actor->email ?? '')),
            'phone' => (string) ($actor->phone ?? ''),
            'roleKey' => $normalizedRole,
            'roleLabel' => $this->roleLabel($normalizedRole),
            'accountStatus' => $accountStatus,
            'subscriptionStatus' => strtolower((string) ($actor->subscription_status ?? 'active')),
            'statusLabel' => $statusLabel,
            'statusTone' => $statusTone,
            'lastActiveAt' => $lastActiveAt,
            'createdAt' => $this->toIso8601($actor->created_at ?? null),
            'updatedAt' => $this->toIso8601($actor->updated_at ?? null),
            'lastActiveTimestamp' => $this->toTimestamp($lastActiveAt),
        ];
    }

    private function roleLabel(string $roleKey): string
    {
        return match ($roleKey) {
            'ADMIN' => 'Administrateur',
            'OWNER' => 'Proprietaire de parking',
            default => 'Client',
        };
    }

    private function normalizeAccountStatus(string $value): string
    {
        return strtolower($value) === 'blocked' ? 'blocked' : 'active';
    }

    private function accountEvents(int $perSource): Collection
    {
        $adminEvents = Admin::query()
            ->orderByDesc('updated_at')
            ->take($perSource)
            ->get()
            ->map(function (Admin $admin): array {
                $occurredAt = $this->toIso8601($admin->updated_at ?? $admin->created_at ?? null);

                return $this->buildEvent(
                    eventId: sprintf('account-admin-%s', (string) $admin->getKey()),
                    category: 'Compte',
                    categoryTone: 'info',
                    action: 'Compte admin actif',
                    details: trim(sprintf('%s (%s)', (string) ($admin->name ?? ''), (string) ($admin->email ?? ''))),
                    actor: (string) ($admin->name ?? $admin->email ?? ''),
                    occurredAt: $occurredAt
                );
            });

        $ownerEvents = ParkingOwner::query()
            ->orderByDesc('updated_at')
            ->take($perSource)
            ->get()
            ->map(function (ParkingOwner $owner): array {
                $accountStatus = $this->normalizeAccountStatus((string) ($owner->account_status ?? 'active'));
                $subscriptionStatus = strtolower((string) ($owner->subscription_status ?? 'active'));
                $occurredAt = $this->toIso8601(
                    $owner->blocked_at
                        ?? $owner->updated_at
                        ?? $owner->created_at
                        ?? null
                );

                $action = $accountStatus === 'blocked' ? 'Owner suspendu' : 'Owner actif';
                $tone = $accountStatus === 'blocked' ? 'danger' : 'warning';

                return $this->buildEvent(
                    eventId: sprintf('account-owner-%s', (string) $owner->getKey()),
                    category: 'Compte',
                    categoryTone: $tone,
                    action: $action,
                    details: trim(sprintf('%s | abonnement: %s', (string) ($owner->email ?? ''), $subscriptionStatus)),
                    actor: (string) ($owner->name ?? $owner->email ?? ''),
                    occurredAt: $occurredAt
                );
            });

        $clientEvents = User::query()
            ->orderByDesc('updated_at')
            ->take($perSource)
            ->get()
            ->map(function (User $client): array {
                $occurredAt = $this->toIso8601($client->updated_at ?? $client->created_at ?? null);

                return $this->buildEvent(
                    eventId: sprintf('account-client-%s', (string) $client->getKey()),
                    category: 'Compte',
                    categoryTone: 'neutral',
                    action: 'Compte client actif',
                    details: trim(sprintf('%s (%s)', (string) ($client->name ?? ''), (string) ($client->email ?? ''))),
                    actor: (string) ($client->name ?? $client->email ?? ''),
                    occurredAt: $occurredAt
                );
            });

        return $adminEvents
            ->concat($ownerEvents)
            ->concat($clientEvents);
    }

    private function parkingEvents(int $limit): Collection
    {
        return Parking::query()
            ->orderByDesc('updated_at')
            ->take($limit)
            ->get()
            ->map(function (Parking $parking): array {
                $createdAt = $this->toIso8601($parking->created_at ?? null);
                $updatedAt = $this->toIso8601($parking->updated_at ?? null);
                $occurredAt = $updatedAt ?: $createdAt;
                $isUpdated = $createdAt && $updatedAt && $createdAt !== $updatedAt;

                $ownerAccount = (array) ($parking->owner_account ?? []);
                $ownerEmail = (string) ($ownerAccount['email'] ?? '');

                return $this->buildEvent(
                    eventId: sprintf('parking-%s', (string) $parking->getKey()),
                    category: 'Parking',
                    categoryTone: 'info',
                    action: $isUpdated ? 'Parking mis a jour' : 'Parking cree',
                    details: trim(sprintf('%s | owner: %s', (string) ($parking->name ?? ''), $ownerEmail)),
                    actor: (string) ($parking->updated_by_admin_id ?: $parking->created_by_admin_id ?: '-'),
                    occurredAt: $occurredAt
                );
            });
    }

    private function reservationEvents(int $limit): Collection
    {
        return Reservation::query()
            ->orderByDesc('updated_at')
            ->take($limit)
            ->get()
            ->map(function (Reservation $reservation): array {
                $status = strtolower((string) ($reservation->reservation_status ?? 'pending_payment'));
                $occurredAt = $this->toIso8601($reservation->updated_at ?? $reservation->created_at ?? null);

                [$action, $tone] = match ($status) {
                    'confirmed' => ['Reservation confirmee', 'success'],
                    'in_transit' => ['Client en route', 'info'],
                    'completed' => ['Reservation terminee', 'success'],
                    'cancelled_by_user' => ['Reservation annulee par client', 'danger'],
                    'cancelled_timeout' => ['Reservation annulee (timeout)', 'danger'],
                    default => ['Reservation en attente paiement', 'warning'],
                };

                return $this->buildEvent(
                    eventId: sprintf('reservation-%s', (string) $reservation->getKey()),
                    category: 'Reservation',
                    categoryTone: $tone,
                    action: $action,
                    details: trim(sprintf('%s | statut paiement: %s', (string) ($reservation->parking_name ?? ''), (string) ($reservation->payment_status ?? 'unpaid'))),
                    actor: (string) ($reservation->user_id ?? '-'),
                    occurredAt: $occurredAt
                );
            });
    }

    private function paymentEvents(int $limit): Collection
    {
        return Payment::query()
            ->orderByDesc('updated_at')
            ->take($limit)
            ->get()
            ->map(function (Payment $payment): array {
                $status = strtolower((string) ($payment->status ?? 'idle'));
                $occurredAt = $this->toIso8601($payment->updated_at ?? $payment->created_at ?? null);

                [$action, $tone] = match ($status) {
                    'success' => ['Paiement confirme', 'success'],
                    'failed' => ['Paiement echoue', 'danger'],
                    'timeout' => ['Paiement en timeout', 'warning'],
                    default => ['Paiement initie', 'info'],
                };

                return $this->buildEvent(
                    eventId: sprintf('payment-%s', (string) $payment->getKey()),
                    category: 'Paiement',
                    categoryTone: $tone,
                    action: $action,
                    details: trim(sprintf('%s MAD | %s', number_format((float) ($payment->amount ?? 0), 2, '.', ''), (string) ($payment->method ?? 'edahabia'))),
                    actor: (string) ($payment->user_id ?? '-'),
                    occurredAt: $occurredAt
                );
            });
    }

    private function buildEvent(
        string $eventId,
        string $category,
        string $categoryTone,
        string $action,
        string $details,
        string $actor,
        ?string $occurredAt
    ): array {
        return [
            'eventId' => $eventId,
            'category' => $category,
            'categoryTone' => $categoryTone,
            'action' => $action,
            'details' => $details,
            'actor' => $actor,
            'occurredAt' => $occurredAt,
            'occurredAtTimestamp' => $this->toTimestamp($occurredAt),
        ];
    }

    private function toIso8601(mixed $value): ?string
    {
        if (! $value) {
            return null;
        }

        if ($value instanceof CarbonInterface) {
            return $value->toIso8601String();
        }

        try {
            return Carbon::parse((string) $value)->toIso8601String();
        } catch (\Throwable) {
            return null;
        }
    }

    private function toTimestamp(?string $isoDate): int
    {
        if (! $isoDate) {
            return 0;
        }

        $timestamp = strtotime($isoDate);

        return $timestamp !== false ? $timestamp : 0;
    }
}
