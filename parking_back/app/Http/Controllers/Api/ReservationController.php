<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Reservation\CreateReservationRequest;
use App\Models\Reservation;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ReservationController extends Controller
{
    private const STATUS_PENDING_PAYMENT = 'pending_payment';

    private const STATUS_CONFIRMED = 'confirmed';

    private const STATUS_IN_TRANSIT = 'in_transit';

    private const STATUS_COMPLETED = 'completed';

    private const STATUS_CANCELLED_BY_USER = 'cancelled_by_user';

    private const STATUS_CANCELLED_TIMEOUT = 'cancelled_timeout';

    public function store(CreateReservationRequest $request): JsonResponse
    {
        $user = $request->user('user');
        $payload = $request->validated();

        $activeStatuses = [
            self::STATUS_PENDING_PAYMENT,
            self::STATUS_CONFIRMED,
            self::STATUS_IN_TRANSIT,
        ];

        $currentActiveReservations = Reservation::query()
            ->where('user_id', (string) $user->getAuthIdentifier())
            ->whereIn('reservation_status', $activeStatuses)
            ->get();

        foreach ($currentActiveReservations as $currentActiveReservation) {
            $this->refreshTimeoutStatus($currentActiveReservation);
        }

        $hasActiveReservation = Reservation::query()
            ->where('user_id', (string) $user->getAuthIdentifier())
            ->whereIn('reservation_status', $activeStatuses)
            ->exists();

        if ($hasActiveReservation) {
            return response()->json([
                'message' => 'Vous avez deja une reservation en cours. Terminez ou annulez-la avant d en creer une nouvelle.',
            ], 422);
        }

        $durationType = (string) $payload['duration_type'];
        $isShortDuration = $durationType === 'courte';

        $reservation = Reservation::query()->create([
            'user_id' => (string) $user->getAuthIdentifier(),
            'parking_name' => (string) $payload['parking_name'],
            'parking_address' => (string) ($payload['parking_address'] ?? ''),
            'equipments' => $payload['equipments'] ?? [],
            'duration_type' => $durationType,
            'duration_minutes' => (int) ($payload['duration_minutes'] ?? 0),
            'amount' => (float) ($payload['amount'] ?? 0),
            'deposit_required' => ! $isShortDuration,
            'deposit_amount' => $isShortDuration ? 0.0 : (float) ($payload['deposit_amount'] ?? 200.0),
            'reservation_status' => $isShortDuration ? self::STATUS_CONFIRMED : self::STATUS_PENDING_PAYMENT,
            'payment_status' => $isShortDuration ? 'not_required' : 'unpaid',
            'expires_at' => CarbonImmutable::now()->addMinutes(30),
            'cancelled_at' => null,
        ]);

        return response()->json([
            'message' => 'Reservation created successfully.',
            'data' => [
                'reservation' => $this->transformReservation($reservation),
            ],
        ], 201);
    }

    public function index(Request $request): JsonResponse
    {
        $user = $request->user('user');

        $reservations = Reservation::query()
            ->where('user_id', (string) $user->getAuthIdentifier())
            ->orderByDesc('created_at')
            ->get()
            ->map(function (Reservation $reservation): array {
                $this->refreshTimeoutStatus($reservation);

                return $this->transformReservation($reservation);
            })
            ->values();

        return response()->json([
            'message' => 'Reservations retrieved successfully.',
            'data' => $reservations,
        ]);
    }

    public function show(Request $request, string $reservationId): JsonResponse
    {
        $reservation = $this->findOwnedReservation($request, $reservationId);

        if (! $reservation) {
            return response()->json([
                'message' => 'Reservation not found.',
            ], 404);
        }

        $this->refreshTimeoutStatus($reservation);

        return response()->json([
            'message' => 'Reservation retrieved successfully.',
            'data' => $this->transformReservation($reservation),
        ]);
    }

    public function cancel(Request $request, string $reservationId): JsonResponse
    {
        $reservation = $this->findOwnedReservation($request, $reservationId);

        if (! $reservation) {
            return response()->json([
                'message' => 'Reservation not found.',
            ], 404);
        }

        $this->refreshTimeoutStatus($reservation);

        $status = (string) ($reservation->reservation_status ?? self::STATUS_PENDING_PAYMENT);

        if ($this->isCancelledStatus($status)) {
            return response()->json([
                'message' => 'Reservation is already cancelled.',
                'data' => $this->transformReservation($reservation),
            ]);
        }

        if ($status === self::STATUS_COMPLETED) {
            return response()->json([
                'message' => 'Completed reservation cannot be cancelled.',
            ], 422);
        }

        $reservation->reservation_status = self::STATUS_CANCELLED_BY_USER;
        $reservation->cancelled_at = CarbonImmutable::now();
        if ((string) $reservation->payment_status !== 'paid') {
            $reservation->payment_status = 'cancelled';
        }
        $reservation->save();

        return response()->json([
            'message' => 'Reservation cancelled successfully.',
            'data' => $this->transformReservation($reservation),
        ]);
    }

    public function go(Request $request, string $reservationId): JsonResponse
    {
        $reservation = $this->findOwnedReservation($request, $reservationId);

        if (! $reservation) {
            return response()->json([
                'message' => 'Reservation not found.',
            ], 404);
        }

        $this->refreshTimeoutStatus($reservation);

        $status = (string) ($reservation->reservation_status ?? self::STATUS_PENDING_PAYMENT);

        if ($status === self::STATUS_COMPLETED) {
            return response()->json([
                'message' => 'Reservation already completed.',
                'data' => $this->transformReservation($reservation),
            ]);
        }

        if ($this->isCancelledStatus($status)) {
            return response()->json([
                'message' => 'Cancelled reservation cannot switch to en route.',
            ], 422);
        }

        if ($status === self::STATUS_PENDING_PAYMENT) {
            return response()->json([
                'message' => 'Complete payment before using S y rendre.',
            ], 422);
        }

        if ($status === self::STATUS_IN_TRANSIT) {
            return response()->json([
                'message' => 'Reservation already marked as en route.',
                'data' => $this->transformReservation($reservation),
            ]);
        }

        $reservation->reservation_status = self::STATUS_IN_TRANSIT;
        $reservation->cancelled_at = null;
        $reservation->save();

        return response()->json([
            'message' => 'Reservation is now en route.',
            'data' => $this->transformReservation($reservation),
        ]);
    }

    public function scanTicket(Request $request, string $reservationId): JsonResponse
    {
        $reservation = $this->findOwnedReservation($request, $reservationId);

        if (! $reservation) {
            return response()->json([
                'message' => 'Reservation not found.',
            ], 404);
        }

        $this->refreshTimeoutStatus($reservation);

        $status = (string) ($reservation->reservation_status ?? self::STATUS_PENDING_PAYMENT);

        if ($status === self::STATUS_COMPLETED) {
            return response()->json([
                'message' => 'Reservation already completed.',
                'data' => $this->transformReservation($reservation),
            ]);
        }

        if ($this->isCancelledStatus($status)) {
            return response()->json([
                'message' => 'Cancelled reservation cannot be completed.',
            ], 422);
        }

        if ($status === self::STATUS_PENDING_PAYMENT) {
            return response()->json([
                'message' => 'Payment is required before ticket scan.',
            ], 422);
        }

        if ($status !== self::STATUS_IN_TRANSIT) {
            return response()->json([
                'message' => 'Use S y rendre first, then scan the ticket on arrival.',
            ], 422);
        }

        $reservation->reservation_status = self::STATUS_COMPLETED;
        $reservation->cancelled_at = null;
        $reservation->save();

        return response()->json([
            'message' => 'Ticket scanned. Reservation marked as completed.',
            'data' => $this->transformReservation($reservation),
        ]);
    }

    private function findOwnedReservation(Request $request, string $reservationId): ?Reservation
    {
        $user = $request->user('user');
        $reservation = Reservation::query()->find($reservationId);

        if (! $reservation || (string) $reservation->user_id !== (string) $user->getAuthIdentifier()) {
            return null;
        }

        return $reservation;
    }

    private function refreshTimeoutStatus(Reservation $reservation): void
    {
        $status = (string) ($reservation->reservation_status ?? self::STATUS_PENDING_PAYMENT);

        if (! in_array($status, [self::STATUS_PENDING_PAYMENT, self::STATUS_CONFIRMED, self::STATUS_IN_TRANSIT], true)) {
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
        $reservation->cancelled_at = CarbonImmutable::now();
        if ((string) $reservation->payment_status !== 'paid') {
            $reservation->payment_status = 'cancelled';
        }
        $reservation->save();
    }

    private function isCancelledStatus(string $status): bool
    {
        return in_array($status, [
            self::STATUS_CANCELLED_BY_USER,
            self::STATUS_CANCELLED_TIMEOUT,
            'cancelled',
            'expired',
        ], true);
    }

    private function transformReservation(Reservation $reservation): array
    {
        return [
            'id' => (string) $reservation->getKey(),
            'user_id' => (string) $reservation->user_id,
            'parking_name' => (string) $reservation->parking_name,
            'parking_address' => (string) ($reservation->parking_address ?? ''),
            'equipments' => (array) ($reservation->equipments ?? []),
            'duration_type' => (string) $reservation->duration_type,
            'duration_minutes' => (int) ($reservation->duration_minutes ?? 0),
            'amount' => (float) ($reservation->amount ?? 0),
            'deposit_required' => (bool) ($reservation->deposit_required ?? false),
            'deposit_amount' => (float) ($reservation->deposit_amount ?? 0),
            'reservation_status' => (string) ($reservation->reservation_status ?? self::STATUS_PENDING_PAYMENT),
            'payment_status' => (string) ($reservation->payment_status ?? 'unpaid'),
            'expires_at' => $reservation->expires_at?->toIso8601String(),
            'cancelled_at' => $reservation->cancelled_at?->toIso8601String(),
            'created_at' => $reservation->created_at?->toIso8601String(),
            'updated_at' => $reservation->updated_at?->toIso8601String(),
        ];
    }
}
