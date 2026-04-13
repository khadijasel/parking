<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Payment\ConfirmPaymentRequest;
use App\Http\Requests\Payment\InitiatePaymentRequest;
use App\Models\Payment;
use App\Models\ParkingSession;
use App\Models\Reservation;
use App\Services\Payment\MockBankService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PaymentController extends Controller
{
    private const STATUS_CONFIRMED = 'confirmed';

    private const STATUS_IN_TRANSIT = 'in_transit';

    private const STATUS_CANCELLED_BY_USER = 'cancelled_by_user';

    private const STATUS_CANCELLED_TIMEOUT = 'cancelled_timeout';

    private const STATUS_COMPLETED = 'completed';

    private const SESSION_STATUS_ACTIVE = 'active';

    public function __construct(private readonly MockBankService $mockBankService)
    {
    }

    public function initiate(InitiatePaymentRequest $request): JsonResponse
    {
        $user = $request->user('user');
        $payload = $request->validated();

        $reservation = Reservation::query()->find((string) $payload['reservation_id']);

        if (! $reservation || (string) $reservation->user_id !== (string) $user->getAuthIdentifier()) {
            return response()->json([
                'message' => 'Reservation not found.',
            ], 404);
        }

        $this->refreshTimeoutStatus($reservation);

        $activeSession = $this->findActiveSessionForReservation((string) $reservation->getKey());
        $hasActiveSession = $activeSession instanceof ParkingSession;

        if ($hasActiveSession) {
            $startedAt = $activeSession->started_at
                ? CarbonImmutable::instance($activeSession->started_at)
                : null;

            if ($startedAt && $this->hasSuccessfulPaymentForSession((string) $reservation->getKey(), $startedAt)) {
                return response()->json([
                    'message' => 'Current parking session is already paid.',
                ], 422);
            }
        }

        if (! $hasActiveSession && (string) $reservation->payment_status === 'paid') {
            return response()->json([
                'message' => 'Reservation is already paid.',
            ], 422);
        }

        if ($this->isBlockedForPayment($reservation, $hasActiveSession)) {
            return response()->json([
                'message' => 'Reservation cannot be paid in its current status.',
            ], 422);
        }

        $payment = Payment::query()->create([
            'user_id' => (string) $user->getAuthIdentifier(),
            'reservation_id' => (string) $reservation->getKey(),
            'parking_name' => (string) $reservation->parking_name,
            'duration_minutes' => $this->resolveDurationMinutes($reservation, $payload, $hasActiveSession),
            'amount' => $this->resolveAmount($reservation, $payload, $hasActiveSession),
            'method' => (string) $payload['method'],
            'status' => 'idle',
            'transaction_ref' => 'SP-'.random_int(10000, 99999),
            'pin_attempts' => 0,
            'remaining_attempts' => MockBankService::MAX_ATTEMPTS,
            'error_code' => null,
            'error_message' => null,
            'paid_at' => null,
        ]);

        return response()->json([
            'message' => 'Payment transaction initiated successfully.',
            'data' => [
                'transaction' => $this->transformPayment($payment),
            ],
        ], 201);
    }

    public function confirm(ConfirmPaymentRequest $request): JsonResponse
    {
        $user = $request->user('user');
        $payload = $request->validated();

        $payment = Payment::query()->find((string) $payload['transaction_id']);

        if (! $payment || (string) $payment->user_id !== (string) $user->getAuthIdentifier()) {
            return response()->json([
                'message' => 'Transaction not found.',
            ], 404);
        }

        if ((string) $payment->status === 'success') {
            return response()->json([
                'message' => 'Payment already confirmed.',
                'data' => [
                    'success' => true,
                    'status' => 'success',
                    'transaction' => $this->transformPayment($payment),
                ],
            ]);
        }

        // Always use the method selected by the client at confirmation time.
        $payment->method = (string) $payload['method'];

        $result = $this->mockBankService->process($payment, $payload['pin'] ?? null);
        $freshPayment = $payment->fresh() ?? $payment;

        if ($result['success'] === true) {
            $reservation = Reservation::query()->find((string) $payment->reservation_id);
            if ($reservation && (string) $reservation->user_id === (string) $user->getAuthIdentifier()) {
                $reservation->payment_status = 'paid';
                if ((string) $reservation->reservation_status === 'pending_payment') {
                    $reservation->reservation_status = 'confirmed';
                }

                if ((string) $reservation->duration_type !== 'courte') {
                    $reservation->expires_at = CarbonImmutable::now()->addHour();
                }

                $reservation->save();
            }
        }

        $statusCode = $result['success'] === true ? 200 : 422;

        return response()->json([
            'message' => $result['success'] ? 'Payment confirmed successfully.' : 'Payment failed.',
            'data' => [
                'success' => (bool) $result['success'],
                'status' => (string) $result['status'],
                'error_code' => $result['error_code'],
                'error_message' => $result['error_message'],
                'remaining_attempts' => (int) $result['remaining_attempts'],
                'transaction' => $this->transformPayment($freshPayment),
            ],
        ], $statusCode);
    }

    public function history(Request $request): JsonResponse
    {
        $user = $request->user('user');

        $history = Payment::query()
            ->where('user_id', (string) $user->getAuthIdentifier())
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (Payment $payment): array => $this->transformPayment($payment))
            ->values();

        return response()->json([
            'message' => 'Payment history retrieved successfully.',
            'data' => $history,
        ]);
    }

    private function transformPayment(Payment $payment): array
    {
        return [
            'id' => (string) $payment->getKey(),
            'session_id' => (string) $payment->reservation_id,
            'user_id' => (string) $payment->user_id,
            'parking_name' => (string) ($payment->parking_name ?? ''),
            'montant' => (float) ($payment->amount ?? 0),
            'duree_minutes' => (int) ($payment->duration_minutes ?? 0),
            'methode' => (string) ($payment->method ?? 'edahabia'),
            'statut' => (string) ($payment->status ?? 'idle'),
            'transaction_ref' => (string) ($payment->transaction_ref ?? ''),
            'created_at' => $payment->created_at?->toIso8601String(),
            'paid_at' => $payment->paid_at?->toIso8601String(),
            'error_code' => $payment->error_code,
            'error_message' => $payment->error_message,
            'remaining_attempts' => (int) ($payment->remaining_attempts ?? MockBankService::MAX_ATTEMPTS),
        ];
    }

    private function refreshTimeoutStatus(Reservation $reservation): void
    {
        $status = (string) ($reservation->reservation_status ?? 'pending_payment');

        if (! in_array($status, ['pending_payment', self::STATUS_CONFIRMED, self::STATUS_IN_TRANSIT], true)) {
            return;
        }

        $expiresAt = $reservation->expires_at;
        if (! $expiresAt) {
            return;
        }

        $expiresAtImmutable = CarbonImmutable::instance($expiresAt);
        if (CarbonImmutable::now()->lt($expiresAtImmutable)) {
            return;
        }

        $reservation->reservation_status = self::STATUS_CANCELLED_TIMEOUT;
        if ((string) $reservation->payment_status !== 'paid') {
            $reservation->payment_status = 'cancelled';
        }
        $reservation->save();
    }

    private function isBlockedForPayment(Reservation $reservation, bool $hasActiveSession): bool
    {
        $status = (string) ($reservation->reservation_status ?? 'pending_payment');
        $isShortDuration = (string) ($reservation->duration_type ?? '') === 'courte';

        if ($status === self::STATUS_COMPLETED && $hasActiveSession) {
            return false;
        }

        if ($status === self::STATUS_COMPLETED && $isShortDuration) {
            return false;
        }

        return in_array($status, [
            self::STATUS_CANCELLED_BY_USER,
            self::STATUS_CANCELLED_TIMEOUT,
            self::STATUS_COMPLETED,
            'cancelled',
            'expired',
        ], true);
    }

    private function resolveAmount(Reservation $reservation, array $payload, bool $hasActiveSession): float
    {
        $isShortDuration = (string) ($reservation->duration_type ?? '') === 'courte';
        $providedAmount = (float) ($payload['amount'] ?? 0);

        if (! $isShortDuration) {
            if ($hasActiveSession) {
                $amount = (float) ($reservation->amount ?? 0);
                if ($amount > 0) {
                    return $amount;
                }

                if ($providedAmount > 0) {
                    return $providedAmount;
                }

                return $this->resolveLongDurationFallbackAmount((string) ($reservation->duration_type ?? ''));
            }

            $depositAmount = (float) ($reservation->deposit_amount ?? 0);
            if ($depositAmount > 0) {
                return $depositAmount;
            }

            if ($providedAmount > 0) {
                return $providedAmount;
            }

            return 200.0;
        }

        if ($providedAmount > 0) {
            return $providedAmount;
        }

        return $this->resolveDurationMinutes($reservation, $payload, $hasActiveSession) * (150.0 / 60.0);
    }

    private function resolveDurationMinutes(Reservation $reservation, array $payload, bool $hasActiveSession): int
    {
        $isShortDuration = (string) ($reservation->duration_type ?? '') === 'courte';
        $provided = (int) ($payload['duration_minutes'] ?? 0);

        if (! $isShortDuration) {
            return max(0, (int) ($reservation->duration_minutes ?? 0));
        }

        if ($provided > 0) {
            return $provided;
        }

        if ($hasActiveSession) {
            return max(1, (int) ($reservation->duration_minutes ?? 0));
        }

        return max(0, (int) ($reservation->duration_minutes ?? 0));
    }

    private function resolveLongDurationFallbackAmount(string $durationType): float
    {
        return match ($durationType) {
            'journee' => 800.0,
            'semaine' => 4500.0,
            'mois' => 15000.0,
            default => 0.0,
        };
    }

    private function findActiveSessionForReservation(string $reservationId): ?ParkingSession
    {
        if ($reservationId === '') {
            return null;
        }

        return ParkingSession::query()
            ->where('reservation_id', $reservationId)
            ->where('status', self::SESSION_STATUS_ACTIVE)
            ->orderByDesc('started_at')
            ->first();
    }

    private function hasSuccessfulPaymentForSession(string $reservationId, CarbonImmutable $sessionStartedAt): bool
    {
        if ($reservationId === '') {
            return false;
        }

        $threshold = $sessionStartedAt->subSeconds(5);

        $payments = Payment::query()
            ->where('reservation_id', $reservationId)
            ->where('status', 'success')
            ->orderByDesc('paid_at')
            ->orderByDesc('created_at')
            ->get();

        foreach ($payments as $payment) {
            $paidAt = $payment->paid_at
                ? CarbonImmutable::instance($payment->paid_at)
                : ($payment->created_at ? CarbonImmutable::instance($payment->created_at) : null);

            if (! $paidAt) {
                continue;
            }

            if ($paidAt->greaterThanOrEqualTo($threshold)) {
                return true;
            }
        }

        return false;
    }
}
