<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Payment;
use App\Http\Requests\Reservation\CreateReservationRequest;
use App\Models\ParkingAvailability;
use App\Models\ParkingSession;
use App\Models\Reservation;
use App\Services\Parking\ParkingAvailabilityService;
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

    private const SESSION_STATUS_ACTIVE = 'active';

    private const SESSION_STATUS_COMPLETED = 'completed';

    public function __construct(private readonly ParkingAvailabilityService $parkingAvailabilityService)
    {
    }

    public function store(CreateReservationRequest $request): JsonResponse
    {
        $user = $request->user('user');
        $payload = $request->validated();

        $parkingName = (string) ($payload['parking_name'] ?? '');
        $parkingId = trim((string) ($payload['parking_id'] ?? ''));

        if ($parkingId === '' && $parkingName !== '') {
            $availability = ParkingAvailability::query()
                ->where('parking_name', $parkingName)
                ->first();

            if ($availability instanceof ParkingAvailability) {
                $parkingId = trim((string) ($availability->parking_id ?? ''));
            }
        }

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

        if (! $this->parkingAvailabilityService->lockSpot(
            $parkingName,
            $parkingId,
        )) {
            return response()->json([
                'message' => 'Aucune place disponible pour ce parking.',
            ], 422);
        }

        $durationType = (string) $payload['duration_type'];
        $isShortDuration = $durationType === 'courte';

        try {
            $reservation = Reservation::query()->create([
                'user_id' => (string) $user->getAuthIdentifier(),
                'parking_id' => $parkingId,
                'parking_name' => $parkingName,
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
                'spot_locked' => true,
            ]);
        } catch (\Throwable $e) {
            $this->parkingAvailabilityService->releaseSpot(
                $parkingName,
                $parkingId,
            );

            throw $e;
        }

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

        $this->releaseSpotIfLocked($reservation);
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
            $activeSession = $this->findActiveParkingSession((string) $reservation->user_id);

            return response()->json([
                'message' => 'Reservation already completed.',
                'data' => array_merge(
                    $this->transformReservation($reservation),
                    [
                        'parking_session' => $activeSession ? $this->transformParkingSession($activeSession) : null,
                    ],
                ),
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

        if (! in_array($status, [self::STATUS_IN_TRANSIT, self::STATUS_CONFIRMED], true)) {
            return response()->json([
                'message' => 'Reservation must be confirmed or en route before ticket scan.',
            ], 422);
        }

        $reservation->reservation_status = self::STATUS_COMPLETED;
        $reservation->cancelled_at = null;
        $reservation->expires_at = null;
        $reservation->save();

        $parkingSession = $this->createParkingSessionFromReservation($reservation);

        return response()->json([
            'message' => 'Ticket scanned. Reservation marked as completed.',
            'data' => array_merge(
                $this->transformReservation($reservation),
                [
                    'parking_session' => $this->transformParkingSession($parkingSession),
                ],
            ),
        ]);
    }

    public function currentSession(Request $request): JsonResponse
    {
        $user = $request->user('user');

        $activeSession = $this->findActiveParkingSession((string) $user->getAuthIdentifier());

        return response()->json([
            'message' => 'Current parking session retrieved successfully.',
            'data' => $activeSession ? $this->transformParkingSession($activeSession) : null,
        ]);
    }

    public function exitSession(Request $request): JsonResponse
    {
        $user = $request->user('user');

        $activeSession = $this->findActiveParkingSession((string) $user->getAuthIdentifier());

        if (! $activeSession) {
            return response()->json([
                'message' => 'No active parking session found.',
            ], 404);
        }

        $reservationId = (string) ($activeSession->reservation_id ?? '');
        $reservation = $reservationId === ''
            ? null
            : Reservation::query()->find($reservationId);

        if ($reservation instanceof Reservation) {
            $startedAt = $activeSession->started_at
                ? CarbonImmutable::instance($activeSession->started_at)
                : null;

            $hasSessionPayment = $startedAt
                && $this->hasSuccessfulPaymentForSession((string) $reservation->getKey(), $startedAt);

            if (! $hasSessionPayment) {
                return response()->json([
                    'message' => 'Paiement requis avant la sortie. Veuillez payer la session.',
                    'errors' => [
                        'payment' => ['Paiement requis avant la sortie.'],
                    ],
                ], 422);
            }
        }

        $this->closeActiveSession($activeSession);

        return response()->json([
            'message' => 'Parking session closed successfully.',
            'data' => $this->transformParkingSession($activeSession),
        ]);
    }

    public function sessionHistory(Request $request): JsonResponse
    {
        $user = $request->user('user');

        $history = ParkingSession::query()
            ->where('user_id', (string) $user->getAuthIdentifier())
            ->where('status', self::SESSION_STATUS_COMPLETED)
            ->orderByDesc('ended_at')
            ->orderByDesc('started_at')
            ->get()
            ->map(fn (ParkingSession $session): array => $this->transformParkingSession($session))
            ->values();

        return response()->json([
            'message' => 'Parking session history retrieved successfully.',
            'data' => $history,
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

        $this->releaseSpotIfLocked($reservation);
        $reservation->save();
    }

    private function releaseSpotIfLocked(Reservation $reservation): void
    {
        if ((bool) ($reservation->spot_locked ?? false) !== true) {
            return;
        }

        $this->parkingAvailabilityService->releaseSpot(
            (string) ($reservation->parking_name ?? ''),
            (string) ($reservation->parking_id ?? ''),
        );
        $reservation->spot_locked = false;
    }

    private function releaseSpotFromSession(ParkingSession $session): void
    {
        $reservationId = (string) ($session->reservation_id ?? '');
        $reservation = $reservationId === ''
            ? null
            : Reservation::query()->find($reservationId);

        if ($reservation instanceof Reservation) {
            $this->releaseSpotIfLocked($reservation);
            $reservation->save();

            return;
        }

        $parkingName = (string) ($session->parking_name ?? '');
        if ($parkingName !== '') {
            $this->parkingAvailabilityService->releaseSpot($parkingName, null);
        }
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

    private function findActiveParkingSession(string $userId): ?ParkingSession
    {
        $activeSessions = ParkingSession::query()
            ->where('user_id', $userId)
            ->where('status', self::SESSION_STATUS_ACTIVE)
            ->orderByDesc('started_at')
            ->get();

        foreach ($activeSessions as $activeSession) {
            if ($this->isSessionStaleForReservationStatus($activeSession)) {
                $this->closeActiveSession($activeSession);

                continue;
            }

            return $activeSession;
        }

        return null;
    }

    private function createParkingSessionFromReservation(Reservation $reservation): ParkingSession
    {
        $now = CarbonImmutable::now();
        $userId = (string) $reservation->user_id;

        $existingActiveSessions = ParkingSession::query()
            ->where('user_id', $userId)
            ->where('status', self::SESSION_STATUS_ACTIVE)
            ->get();

        foreach ($existingActiveSessions as $existingActiveSession) {
            $this->closeActiveSession($existingActiveSession, $now);
        }

        return ParkingSession::query()->create([
            'user_id' => $userId,
            'reservation_id' => (string) $reservation->getKey(),
            'parking_name' => (string) $reservation->parking_name,
            'parking_address' => (string) ($reservation->parking_address ?? ''),
            'ticket_code' => $this->buildTicketCode($reservation),
            'status' => self::SESSION_STATUS_ACTIVE,
            'started_at' => $now,
            'ended_at' => null,
        ]);
    }

    private function isSessionStaleForReservationStatus(ParkingSession $session): bool
    {
        $reservationId = (string) ($session->reservation_id ?? '');
        if ($reservationId === '') {
            return false;
        }

        $reservation = Reservation::query()->find($reservationId);
        if (! $reservation instanceof Reservation) {
            return true;
        }

        $status = (string) ($reservation->reservation_status ?? self::STATUS_PENDING_PAYMENT);

        // A parking session can stay active while its reservation is completed.
        // We only auto-close sessions when the linked reservation is cancelled.
        return $this->isCancelledStatus($status);
    }

    private function closeActiveSession(ParkingSession $session, ?CarbonImmutable $endedAt = null): void
    {
        if ((string) ($session->status ?? '') !== self::SESSION_STATUS_ACTIVE) {
            return;
        }

        $session->status = self::SESSION_STATUS_COMPLETED;
        $session->ended_at = $endedAt ?? CarbonImmutable::now();

        $this->releaseSpotFromSession($session);
        $session->save();
    }

    private function buildTicketCode(Reservation $reservation): string
    {
        $parkingName = (string) ($reservation->parking_name ?? '');
        $reservationId = (string) $reservation->getKey();
        $parkingCode = $this->resolveParkingCode($parkingName);
        $spotLabel = $this->resolveSpotLabel($parkingName, $reservationId);

        return $parkingCode.'-'.$spotLabel;
    }

    private function resolveParkingCode(string $parkingName): string
    {
        $normalized = strtolower($parkingName);
        if (str_contains($normalized, 'arduino') || str_contains($normalized, 'notre parking')) {
            return 'ARD';
        }

        $parts = preg_split('/[^a-zA-Z0-9]+/', $parkingName) ?: [];
        $stopWords = ['parking', 'de', 'des', 'du', 'la', 'le', 'el', 'al', 'd'];
        $initials = '';

        foreach ($parts as $part) {
            $word = strtolower(trim($part));
            if ($word === '' || in_array($word, $stopWords, true)) {
                continue;
            }

            $initials .= strtoupper($word[0]);
            if (strlen($initials) >= 3) {
                break;
            }
        }

        if ($initials !== '') {
            return $initials;
        }

        $fallback = preg_replace('/[^A-Z0-9]/', '', strtoupper($parkingName)) ?? '';
        if ($fallback === '') {
            return 'SPK';
        }

        return substr($fallback, 0, 3);
    }

    private function resolveSpotLabel(string $parkingName, string $reservationId): string
    {
        $normalized = strtolower($parkingName);
        if (str_contains($normalized, 'arduino') || str_contains($normalized, 'notre parking')) {
            $spot = $this->stableIndex($reservationId, 6) + 1;

            return 'A'.$spot;
        }

        $letters = ['A', 'B', 'C', 'D', 'E', 'F'];
        $level = $this->stableIndex('L'.$reservationId, 3) + 1;
        $letter = $letters[$this->stableIndex('R'.$reservationId, count($letters))];
        $spot = $this->stableIndex('S'.$reservationId, 9) + 1;

        return 'N'.$level.'-'.$letter.$spot;
    }

    private function stableIndex(string $seed, int $modulo): int
    {
        if ($modulo <= 0) {
            return 0;
        }

        $hash = (int) sprintf('%u', crc32($seed));

        return $hash % $modulo;
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

    private function transformParkingSession(ParkingSession $session): array
    {
        $startedAt = $session->started_at ? CarbonImmutable::instance($session->started_at) : null;
        $endedAt = $session->ended_at ? CarbonImmutable::instance($session->ended_at) : null;
        $durationSeconds = null;
        $reservationStatus = '';
        $reservationPaymentStatus = '';
        $reservationDurationType = '';
        $reservationAmount = 0.0;
        $sessionPaymentStatus = 'unpaid';

        if ($startedAt) {
            $rawDuration = $startedAt->diffInSeconds($endedAt ?? CarbonImmutable::now(), false);
            $durationSeconds = max(0, $rawDuration);
        }

        $reservationId = (string) ($session->reservation_id ?? '');
        if ($reservationId !== '') {
            $reservation = Reservation::query()->find($reservationId);
            if ($reservation instanceof Reservation) {
                $this->refreshTimeoutStatus($reservation);
                $reservationStatus = (string) ($reservation->reservation_status ?? '');
                $reservationPaymentStatus = (string) ($reservation->payment_status ?? '');
                $reservationDurationType = (string) ($reservation->duration_type ?? '');
                $reservationAmount = (float) ($reservation->amount ?? 0);

                if ($startedAt) {
                    $sessionPaymentStatus = $this->hasSuccessfulPaymentForSession(
                        (string) $reservation->getKey(),
                        $startedAt,
                    )
                        ? 'paid'
                        : 'unpaid';
                }
            }
        }

        return [
            'id' => (string) $session->getKey(),
            'user_id' => (string) $session->user_id,
            'reservation_id' => (string) $session->reservation_id,
            'parking_name' => (string) ($session->parking_name ?? ''),
            'parking_address' => (string) ($session->parking_address ?? ''),
            'ticket_code' => (string) ($session->ticket_code ?? ''),
            'status' => (string) ($session->status ?? self::SESSION_STATUS_ACTIVE),
            'duration_seconds' => $durationSeconds,
            'reservation_status' => $reservationStatus,
            'reservation_payment_status' => $reservationPaymentStatus,
            'reservation_duration_type' => $reservationDurationType,
            'reservation_amount' => $reservationAmount,
            'session_payment_status' => $sessionPaymentStatus,
            'started_at' => $session->started_at?->toIso8601String(),
            'ended_at' => $session->ended_at?->toIso8601String(),
            'created_at' => $session->created_at?->toIso8601String(),
            'updated_at' => $session->updated_at?->toIso8601String(),
        ];
    }

    private function transformReservation(Reservation $reservation): array
    {
        return [
            'id' => (string) $reservation->getKey(),
            'user_id' => (string) $reservation->user_id,
            'parking_id' => (string) ($reservation->parking_id ?? ''),
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
            'spot_locked' => (bool) ($reservation->spot_locked ?? false),
            'expires_at' => $reservation->expires_at?->toIso8601String(),
            'cancelled_at' => $reservation->cancelled_at?->toIso8601String(),
            'created_at' => $reservation->created_at?->toIso8601String(),
            'updated_at' => $reservation->updated_at?->toIso8601String(),
        ];
    }
}
