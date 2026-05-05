<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Parking;
use App\Models\ParkingSession;
use App\Models\ParkingTicket;
use App\Models\Reservation;
use App\Services\Parking\ParkingAvailabilityService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Arr;
use Illuminate\Support\Str;

class ParkingTicketController extends Controller
{
    private const STATUS_UNPAID = 'unpaid';

    private const STATUS_PAID = 'paid';

    private const STATUS_CLOSED = 'closed';

    private const SESSION_STATUS_ACTIVE = 'active';

    private const SESSION_STATUS_COMPLETED = 'completed';

    public function __construct(private readonly ParkingAvailabilityService $availabilityService)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $this->authorizeIoTRequest($request);

        $limit = (int) $request->query('limit', 30);
        $limit = max(1, min($limit, 200));

        $tickets = ParkingTicket::query()
            ->orderByDesc('entry_time')
            ->orderByDesc('created_at')
            ->limit($limit)
            ->get()
            ->map(fn (ParkingTicket $ticket): array => $this->transformTicket($ticket))
            ->values();

        return response()->json([
            'message' => 'Tickets retrieved successfully.',
            'data' => $tickets,
        ]);
    }

    public function create(Request $request): JsonResponse
    {
        $this->authorizeIoTRequest($request);

        $payload = $request->validate([
            'parking_id' => ['required', 'string', 'max:100'],
            'parking_name' => ['nullable', 'string', 'max:255'],
            'entry_time' => ['nullable', 'date'],
            'spot_label' => ['nullable', 'string', 'max:80'],
        ]);

        $parkingId = trim((string) $payload['parking_id']);
        $parkingName = trim((string) ($payload['parking_name'] ?? ''));
        $spotLabel = trim((string) ($payload['spot_label'] ?? ''));

        $parking = $this->resolveParkingRecord($parkingId, $parkingName);
        if ($parking instanceof Parking) {
            $parkingId = $this->resolveParkingId($parking);
            $parkingName = trim((string) ($parking->name ?? $parkingName));
        }

        $ticketCode = $this->generateTicketCode($parkingName, $spotLabel);
        $entryTime = isset($payload['entry_time'])
            ? CarbonImmutable::parse($payload['entry_time'])
            : CarbonImmutable::now();

        $ticket = ParkingTicket::query()->create([
            'ticket_code' => $ticketCode,
            'parking_id' => $parkingId,
            'parking_name' => $parkingName,
            'spot_label' => $spotLabel,
            'entry_time' => $entryTime,
            'status' => self::STATUS_UNPAID,
            'scan_count' => 0,
            'last_scanned_at' => null,
            'user_id' => null,
            'reservation_id' => null,
            'session_id' => null,
            'paid_at' => null,
            'closed_at' => null,
        ]);

        return response()->json([
            'message' => 'Ticket created successfully.',
            'data' => [
                'ticket' => $this->transformTicket($ticket),
                'qr_payload' => $this->buildQrPayload($ticket),
            ],
        ], 201);
    }

    public function scan(Request $request): JsonResponse
    {
        $user = $request->user('user');

        $payload = $request->validate([
            'ticket_id' => ['nullable', 'string'],
            'ticket_code' => ['nullable', 'string'],
            'parking_id' => ['nullable', 'string'],
        ]);

        $ticket = $this->findTicket(
            (string) ($payload['ticket_id'] ?? ''),
            (string) ($payload['ticket_code'] ?? ''),
        );

        if (! $ticket) {
            return response()->json([
                'message' => 'Ticket introuvable.',
            ], 404);
        }

        if ((string) $ticket->status === self::STATUS_CLOSED) {
            return response()->json([
                'message' => 'Ce ticket est deja ferme.',
                'data' => $this->ticketResponsePayload($ticket),
            ], 422);
        }

        $userId = (string) $user->getAuthIdentifier();
        $activeSession = ParkingSession::query()
            ->where('user_id', $userId)
            ->where('status', self::SESSION_STATUS_ACTIVE)
            ->orderByDesc('started_at')
            ->first();

        if ($activeSession &&
            (string) $activeSession->ticket_code !== '' &&
            (string) $activeSession->ticket_code !== (string) $ticket->ticket_code) {
            return response()->json([
                'message' => 'Une autre session est deja active. Terminez-la avant de scanner un nouveau ticket.',
            ], 422);
        }

        if ($ticket->user_id && (string) $ticket->user_id !== $userId) {
            return response()->json([
                'message' => 'Ce ticket est deja associe a un autre utilisateur.',
            ], 422);
        }

        $ticket->user_id = $userId;

        if (! $activeSession) {
            $reservation = $this->findActiveReservationForUser(
                $userId,
                (string) ($ticket->parking_id ?? ''),
                (string) ($ticket->parking_name ?? ''),
            );

            if ($reservation instanceof Reservation) {
                $this->refreshTimeoutStatus($reservation);
            }

            if ($reservation instanceof Reservation && (string) ($reservation->reservation_status ?? '') !== 'cancelled_timeout') {
                $ticket->reservation_id = (string) $reservation->getKey();
                $ticket->parking_id = (string) ($reservation->parking_id ?? $ticket->parking_id);
                $ticket->parking_name = (string) ($reservation->parking_name ?? $ticket->parking_name);

                if ((string) ($reservation->payment_status ?? '') === self::STATUS_PAID) {
                    $ticket->status = self::STATUS_PAID;
                    $ticket->paid_at = $ticket->paid_at ?? CarbonImmutable::now();
                }

                $spotLabel = $this->ensureReservationSpotLabel($reservation);
                $this->markReservationAsCompleted($reservation);

                $session = $this->createSessionFromReservation(
                    $reservation,
                    (string) ($ticket->ticket_code ?? ''),
                    $spotLabel,
                );
                $ticket->session_id = (string) $session->getKey();

                if (trim((string) ($ticket->spot_label ?? '')) === '' && $spotLabel !== '') {
                    $ticket->spot_label = $spotLabel;
                }
            } else {
                try {
                    [$walkInReservation, $spotLabel] = $this->createWalkInReservationFromTicket($ticket, $userId);
                } catch (\RuntimeException $exception) {
                    return response()->json([
                        'message' => $exception->getMessage(),
                    ], 422);
                }

                $ticket->reservation_id = (string) $walkInReservation->getKey();
                if (trim((string) ($ticket->spot_label ?? '')) === '' && $spotLabel !== '') {
                    $ticket->spot_label = $spotLabel;
                }

                $session = $this->createSessionFromReservation(
                    $walkInReservation,
                    (string) ($ticket->ticket_code ?? ''),
                    $spotLabel,
                );
                $ticket->session_id = (string) $session->getKey();
            }
        }

        $ticket->scan_count = max(0, (int) ($ticket->scan_count ?? 0)) + 1;
        $ticket->last_scanned_at = CarbonImmutable::now();
        $ticket->save();

        return response()->json([
            'message' => 'Ticket scanne avec succes.',
            'data' => $this->ticketResponsePayload($ticket),
        ]);
    }

    public function exit(Request $request, string $ticketId): JsonResponse
    {
        $user = $request->user('user');

        $ticket = $this->findTicket($ticketId, (string) $request->input('ticket_code', ''));

        if (! $ticket) {
            return response()->json([
                'message' => 'Ticket introuvable.',
            ], 404);
        }

        if ($ticket->user_id && (string) $ticket->user_id !== (string) $user->getAuthIdentifier()) {
            return response()->json([
                'message' => 'Ce ticket appartient a un autre utilisateur.',
            ], 403);
        }

        if ((string) $ticket->status !== self::STATUS_PAID) {
            return response()->json([
                'message' => 'Paiement requis avant la sortie.',
            ], 422);
        }

        $session = ParkingSession::query()
            ->where('ticket_code', (string) $ticket->ticket_code)
            ->where('status', self::SESSION_STATUS_ACTIVE)
            ->orderByDesc('started_at')
            ->first();

        if ($session instanceof ParkingSession) {
            $this->closeActiveSession($session);
        }

        $ticket->status = self::STATUS_CLOSED;
        $ticket->closed_at = CarbonImmutable::now();
        $ticket->save();

        return response()->json([
            'message' => 'Ticket valide pour sortie.',
            'data' => $this->ticketResponsePayload($ticket),
        ]);
    }

    private function authorizeIoTRequest(Request $request): void
    {
        $expectedKey = (string) config('services.arduino.key', '');
        $providedKey = (string) $request->header('X-IoT-Key', $request->header('X-Arduino-Key', ''));

        if ($expectedKey !== '' && $providedKey !== $expectedKey) {
            abort(401, 'Unauthorized IoT request.');
        }
    }

    private function findTicket(string $ticketId, string $ticketCode): ?ParkingTicket
    {
        $ticketId = trim($ticketId);
        $ticketCode = trim($ticketCode);

        if ($ticketId !== '') {
            /** @var ParkingTicket|null $ticket */
            $ticket = ParkingTicket::query()->find($ticketId);
            if ($ticket) {
                return $ticket;
            }
        }

        if ($ticketCode !== '') {
            /** @var ParkingTicket|null $ticket */
            $ticket = ParkingTicket::query()->where('ticket_code', $ticketCode)->first();
            if ($ticket) {
                return $ticket;
            }
        }

        return null;
    }

    private function resolveParkingRecord(string $parkingId, string $parkingName): ?Parking
    {
        $parkingId = trim($parkingId);
        $parkingName = trim($parkingName);

        if ($parkingId !== '') {
            /** @var Parking|null $parking */
            $parking = Parking::query()->where('parking_id', $parkingId)->first();
            if ($parking) {
                return $parking;
            }

            /** @var Parking|null $parking */
            $parking = Parking::query()->find($parkingId);
            if ($parking) {
                return $parking;
            }
        }

        if ($parkingName !== '') {
            /** @var Parking|null $parking */
            return Parking::query()->where('name', $parkingName)->first();
        }

        return null;
    }

    private function resolveParkingId(Parking $parking): string
    {
        $parkingId = trim((string) ($parking->parking_id ?? ''));
        if ($parkingId !== '') {
            return $parkingId;
        }

        return (string) $parking->getKey();
    }

    private function generateTicketCode(string $parkingName, ?string $spotLabel = null): string
    {
        $parkingCode = $this->resolveParkingCode($parkingName);
        $random = strtoupper(Str::random(6));

        $spotLabel = trim((string) ($spotLabel ?? ''));
        if ($spotLabel !== '') {
            $normalizedSpot = strtoupper(preg_replace('/[^A-Z0-9]/', '', $spotLabel) ?? '');
            if ($normalizedSpot !== '') {
                return $parkingCode.'-'.$normalizedSpot.'-'.$random;
            }
        }

        return $parkingCode.'-'.$random;
    }

    private function buildReservationTicketCode(Reservation $reservation): string
    {
        $parkingName = (string) ($reservation->parking_name ?? '');
        $reservationId = (string) $reservation->getKey();
        $parkingCode = $this->resolveParkingCode($parkingName);
        $spotLabel = trim((string) ($reservation->spot_label ?? ''));
        if ($spotLabel === '') {
            $spotLabel = $this->resolveSpotLabel($parkingName, $reservationId);
        }

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

    private function resolveSpotLabel(string $parkingName, string $seed): string
    {
        $normalized = strtolower($parkingName);
        if (str_contains($normalized, 'arduino') || str_contains($normalized, 'notre parking')) {
            $labels = ['A1', 'A2', 'A3', 'B1', 'B2', 'B3'];
            $index = $this->stableIndex($seed, count($labels));

            return $labels[$index] ?? 'A1';
        }

        $letters = ['A', 'B', 'C', 'D', 'E', 'F'];
        $level = $this->stableIndex('L'.$seed, 3) + 1;
        $letter = $letters[$this->stableIndex('R'.$seed, count($letters))];
        $spot = $this->stableIndex('S'.$seed, 9) + 1;

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

    private function findActiveReservationForUser(
        string $userId,
        string $parkingId,
        string $parkingName,
    ): ?Reservation {
        $statuses = ['confirmed', 'in_transit'];

        $query = Reservation::query()
            ->where('user_id', $userId)
            ->whereIn('reservation_status', $statuses);

        if ($parkingId !== '') {
            $query->where('parking_id', $parkingId);
        } elseif ($parkingName !== '') {
            $query->where('parking_name', $parkingName);
        }

        return $query->orderByDesc('created_at')->first();
    }

    private function refreshTimeoutStatus(Reservation $reservation): void
    {
        $status = (string) ($reservation->reservation_status ?? '');

        if (! in_array($status, ['pending_payment', 'confirmed', 'in_transit'], true)) {
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

        $reservation->reservation_status = 'cancelled_timeout';
        $reservation->cancelled_at = CarbonImmutable::now();
        if ((string) ($reservation->payment_status ?? '') !== self::STATUS_PAID) {
            $reservation->payment_status = 'cancelled';
        }

        $this->releaseSpotIfLocked($reservation);
        $reservation->save();
    }

    private function markReservationAsCompleted(Reservation $reservation): void
    {
        $status = (string) ($reservation->reservation_status ?? '');

        if ($status === 'completed') {
            return;
        }

        if (in_array($status, ['cancelled_timeout', 'cancelled_by_user', 'cancelled', 'expired'], true)) {
            return;
        }

        $reservation->reservation_status = 'completed';
        $reservation->cancelled_at = null;
        $reservation->expires_at = null;
        $reservation->save();
    }

    private function ensureReservationSpotLabel(Reservation $reservation): string
    {
        $existing = trim((string) ($reservation->spot_label ?? ''));
        if ($existing !== '') {
            return $existing;
        }

        $parking = $this->resolveParkingRecord(
            (string) ($reservation->parking_id ?? ''),
            (string) ($reservation->parking_name ?? ''),
        );

        if ($parking instanceof Parking) {
            $reserved = $this->reserveSpotLabelForParking($parking);
            if (is_string($reserved) && $reserved !== '') {
                $reservation->spot_label = $reserved;
                $reservation->save();
                return $reserved;
            }
        }

        $computed = $this->resolveSpotLabel(
            (string) ($reservation->parking_name ?? ''),
            (string) $reservation->getKey(),
        );
        $reservation->spot_label = $computed;
        $reservation->save();

        return $computed;
    }

    /**
     * @return array{0: Reservation, 1: string}
     */
    private function createWalkInReservationFromTicket(ParkingTicket $ticket, string $userId): array
    {
        $parkingId = trim((string) ($ticket->parking_id ?? ''));
        $parkingName = trim((string) ($ticket->parking_name ?? ''));
        $parkingAddress = '';

        $parking = $this->resolveParkingRecord($parkingId, $parkingName);
        if ($parking instanceof Parking) {
            $parkingId = $this->resolveParkingId($parking);
            $parkingName = trim((string) ($parking->name ?? $parkingName));
            $parkingAddress = trim((string) ($parking->address ?? ''));
        }

        if (! $this->availabilityService->lockSpot($parkingName, $parkingId !== '' ? $parkingId : null)) {
            throw new \RuntimeException('Aucune place disponible pour ce parking.');
        }

        $reservedSpotLabel = null;
        if ($parking instanceof Parking) {
            $preferredLabel = trim((string) ($ticket->spot_label ?? ''));
            if ($preferredLabel === '') {
                $preferredLabel = $this->extractSpotLabelFromTicketCode((string) ($ticket->ticket_code ?? ''));
            }

            $reservedSpotLabel = $this->reserveSpotLabelForParking($parking, $preferredLabel);

            if ($reservedSpotLabel === null && $this->isArduinoSimParking($parking)) {
                $this->availabilityService->releaseSpot($parkingName, $parkingId !== '' ? $parkingId : null);
                throw new \RuntimeException('Aucune place disponible pour ce parking.');
            }
        }

        try {
            $reservation = Reservation::query()->create([
                'user_id' => $userId,
                'parking_id' => $parkingId,
                'parking_name' => $parkingName,
                'parking_address' => $parkingAddress,
                'spot_label' => $reservedSpotLabel ?? '',
                'equipments' => [],
                'duration_type' => 'courte',
                'duration_minutes' => 0,
                'amount' => 0.0,
                'deposit_required' => false,
                'deposit_amount' => 0.0,
                'reservation_status' => 'completed',
                'payment_status' => 'unpaid',
                'expires_at' => null,
                'cancelled_at' => null,
                'spot_locked' => true,
            ]);
        } catch (\Throwable $e) {
            if ($parking instanceof Parking && is_string($reservedSpotLabel) && $reservedSpotLabel !== '') {
                $this->releaseSpotLabelFromParking($parking, $reservedSpotLabel);
            }
            $this->availabilityService->releaseSpot($parkingName, $parkingId !== '' ? $parkingId : null);

            throw $e;
        }

        $spotLabel = trim((string) ($reservation->spot_label ?? ''));
        if ($spotLabel === '') {
            $spotLabel = $this->resolveSpotLabel($parkingName, (string) $reservation->getKey());
            $reservation->spot_label = $spotLabel;
            $reservation->save();
        }

        return [$reservation, $spotLabel];
    }

    private function releaseSpotFromSession(ParkingSession $session): void
    {
        $reservationId = trim((string) ($session->reservation_id ?? ''));
        if ($reservationId !== '') {
            $reservation = Reservation::query()->find($reservationId);
            if ($reservation instanceof Reservation) {
                $this->releaseSpotIfLocked($reservation);
                $reservation->save();

                return;
            }
        }

        $parkingName = (string) ($session->parking_name ?? '');
        if ($parkingName !== '') {
            $this->availabilityService->releaseSpot($parkingName, null);
        }
    }

    private function releaseSpotIfLocked(Reservation $reservation): void
    {
        if ((bool) ($reservation->spot_locked ?? false) !== true) {
            return;
        }

        $spotLabel = trim((string) ($reservation->spot_label ?? ''));
        if ($spotLabel !== '') {
            $parking = $this->resolveParkingRecord(
                (string) ($reservation->parking_id ?? ''),
                (string) ($reservation->parking_name ?? ''),
            );

            if ($parking instanceof Parking) {
                $this->releaseSpotLabelFromParking($parking, $spotLabel);
            }
        }

        $this->availabilityService->releaseSpot(
            (string) ($reservation->parking_name ?? ''),
            (string) ($reservation->parking_id ?? ''),
        );

        $reservation->spot_locked = false;
    }

    private function reserveSpotLabelForParking(Parking $parking, ?string $preferredLabel = null): ?string
    {
        $indoorMap = (array) ($parking->indoor_map ?? []);
        $spots = collect($indoorMap['spots'] ?? [])
            ->map(fn ($spot): array => (array) $spot)
            ->values()
            ->all();

        if (! count($spots) && $this->isArduinoSimParking($parking)) {
            $spots = $this->defaultArduinoSimSpots();
            $indoorMap = [
                ...$indoorMap,
                'spots' => $spots,
            ];
        }

        if (! count($spots)) {
            return null;
        }

        $preferredLabel = strtoupper(trim((string) ($preferredLabel ?? '')));
        $reservedIndex = null;

        if ($preferredLabel !== '') {
            foreach ($spots as $index => $spot) {
                $label = strtoupper(trim((string) ($spot['label'] ?? '')));
                $state = strtoupper(trim((string) ($spot['state'] ?? 'AVAILABLE')));
                if ($label === $preferredLabel && $state === 'AVAILABLE') {
                    $reservedIndex = (int) $index;
                    break;
                }
            }
        }

        if ($reservedIndex === null) {
            foreach ($spots as $index => $spot) {
                $state = strtoupper(trim((string) ($spot['state'] ?? 'AVAILABLE')));
                if ($state === 'AVAILABLE') {
                    $reservedIndex = (int) $index;
                    break;
                }
            }
        }

        if ($reservedIndex === null) {
            return null;
        }

        $label = trim((string) ($spots[$reservedIndex]['label'] ?? ''));
        if ($label === '') {
            return null;
        }

        $spots[$reservedIndex] = [
            ...$spots[$reservedIndex],
            'state' => 'RESERVED',
            'updatedAt' => CarbonImmutable::now()->toIso8601String(),
        ];

        $parking->indoor_map = [
            ...$indoorMap,
            'spots' => $spots,
        ];
        $parking->available_spots = $this->countAvailableSpots($spots);
        $parking->save();

        return $label;
    }

    private function releaseSpotLabelFromParking(Parking $parking, string $spotLabel): void
    {
        $spotLabel = strtoupper(trim($spotLabel));
        if ($spotLabel === '') {
            return;
        }

        $indoorMap = (array) ($parking->indoor_map ?? []);
        $spots = collect($indoorMap['spots'] ?? [])
            ->map(fn ($spot): array => (array) $spot)
            ->values()
            ->all();

        if (! count($spots) && $this->isArduinoSimParking($parking)) {
            $spots = $this->defaultArduinoSimSpots();
        }

        if (! count($spots)) {
            return;
        }

        $didUpdate = false;
        foreach ($spots as $index => $spot) {
            $label = strtoupper(trim((string) ($spot['label'] ?? '')));
            if ($label !== $spotLabel) {
                continue;
            }

            $state = strtoupper(trim((string) ($spot['state'] ?? '')));
            if ($state === 'RESERVED') {
                $spots[$index] = [
                    ...$spot,
                    'state' => 'AVAILABLE',
                    'updatedAt' => CarbonImmutable::now()->toIso8601String(),
                ];
                $didUpdate = true;
            }

            break;
        }

        if (! $didUpdate) {
            return;
        }

        $parking->indoor_map = [
            ...$indoorMap,
            'spots' => $spots,
        ];
        $parking->available_spots = $this->countAvailableSpots($spots);
        $parking->save();
    }

    private function isArduinoSimParking(Parking $parking): bool
    {
        $parkingId = strtolower(trim((string) ($parking->parking_id ?? $parking->getKey())));
        $parkingName = strtolower(trim((string) ($parking->name ?? '')));

        return $parkingId === 'arduino-sim'
            || str_contains($parkingName, 'arduino')
            || str_contains($parkingName, 'notre parking');
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function defaultArduinoSimSpots(): array
    {
        $now = CarbonImmutable::now()->toIso8601String();

        return [
            [
                'spotId' => 'A3',
                'label' => 'A3',
                'row' => 0,
                'col' => 0,
                'type' => 'STANDARD',
                'state' => 'AVAILABLE',
                'sensor' => ['arduinoId' => 'arduino-sim', 'channel' => '', 'topic' => ''],
                'updatedAt' => $now,
            ],
            [
                'spotId' => 'A2',
                'label' => 'A2',
                'row' => 0,
                'col' => 1,
                'type' => 'STANDARD',
                'state' => 'AVAILABLE',
                'sensor' => ['arduinoId' => 'arduino-sim', 'channel' => '', 'topic' => ''],
                'updatedAt' => $now,
            ],
            [
                'spotId' => 'A1',
                'label' => 'A1',
                'row' => 0,
                'col' => 2,
                'type' => 'STANDARD',
                'state' => 'AVAILABLE',
                'sensor' => ['arduinoId' => 'arduino-sim', 'channel' => '', 'topic' => ''],
                'updatedAt' => $now,
            ],
            [
                'spotId' => 'B3',
                'label' => 'B3',
                'row' => 2,
                'col' => 0,
                'type' => 'STANDARD',
                'state' => 'AVAILABLE',
                'sensor' => ['arduinoId' => 'arduino-sim', 'channel' => '', 'topic' => ''],
                'updatedAt' => $now,
            ],
            [
                'spotId' => 'B2',
                'label' => 'B2',
                'row' => 2,
                'col' => 1,
                'type' => 'STANDARD',
                'state' => 'AVAILABLE',
                'sensor' => ['arduinoId' => 'arduino-sim', 'channel' => '', 'topic' => ''],
                'updatedAt' => $now,
            ],
            [
                'spotId' => 'B1',
                'label' => 'B1',
                'row' => 2,
                'col' => 2,
                'type' => 'STANDARD',
                'state' => 'AVAILABLE',
                'sensor' => ['arduinoId' => 'arduino-sim', 'channel' => '', 'topic' => ''],
                'updatedAt' => $now,
            ],
        ];
    }

    private function countAvailableSpots(array $spots): int
    {
        return max(0, collect($spots)
            ->filter(fn (array $spot): bool => strtoupper(trim((string) ($spot['state'] ?? ''))) === 'AVAILABLE')
            ->count());
    }

    private function extractSpotLabelFromTicketCode(string $ticketCode): string
    {
        $source = strtoupper(trim($ticketCode));
        if ($source === '') {
            return '';
        }

        if (preg_match('/\b(A[1-3]|B[1-3])\b/', $source, $matches) === 1) {
            return (string) ($matches[1] ?? '');
        }

        return '';
    }

    private function createSessionFromReservation(Reservation $reservation, string $ticketCode, string $spotLabel = ''): ParkingSession
    {
        $userId = (string) $reservation->user_id;
        $now = CarbonImmutable::now();

        $existingActive = ParkingSession::query()
            ->where('reservation_id', (string) $reservation->getKey())
            ->where('status', self::SESSION_STATUS_ACTIVE)
            ->first();

        if ($existingActive) {
            return $existingActive;
        }

        return ParkingSession::query()->create([
            'user_id' => $userId,
            'reservation_id' => (string) $reservation->getKey(),
            'parking_name' => (string) ($reservation->parking_name ?? ''),
            'parking_address' => (string) ($reservation->parking_address ?? ''),
            'ticket_code' => $ticketCode,
            'spot_label' => $spotLabel,
            'status' => self::SESSION_STATUS_ACTIVE,
            'started_at' => $now,
            'ended_at' => null,
        ]);
    }

    private function createSessionFromTicket(ParkingTicket $ticket): ParkingSession
    {
        $now = CarbonImmutable::now();
        $userId = (string) ($ticket->user_id ?? '');
        $spotLabel = trim((string) ($ticket->spot_label ?? ''));

        $existingActive = ParkingSession::query()
            ->where('ticket_code', (string) $ticket->ticket_code)
            ->where('status', self::SESSION_STATUS_ACTIVE)
            ->first();

        if ($existingActive) {
            return $existingActive;
        }

        return ParkingSession::query()->create([
            'user_id' => $userId,
            'reservation_id' => (string) ($ticket->reservation_id ?? ''),
            'parking_name' => (string) ($ticket->parking_name ?? ''),
            'parking_address' => '',
            'ticket_code' => (string) $ticket->ticket_code,
            'spot_label' => $spotLabel,
            'status' => self::SESSION_STATUS_ACTIVE,
            'started_at' => $now,
            'ended_at' => null,
        ]);
    }

    private function closeActiveSession(ParkingSession $session): void
    {
        if ((string) ($session->status ?? '') !== self::SESSION_STATUS_ACTIVE) {
            return;
        }

        $session->status = self::SESSION_STATUS_COMPLETED;
        $session->ended_at = CarbonImmutable::now();

        $this->releaseSpotFromSession($session);
        $session->save();
    }

    private function transformTicket(ParkingTicket $ticket): array
    {
        return [
            'id' => (string) $ticket->getKey(),
            'ticket_code' => (string) ($ticket->ticket_code ?? ''),
            'parking_id' => (string) ($ticket->parking_id ?? ''),
            'parking_name' => (string) ($ticket->parking_name ?? ''),
            'spot_label' => (string) ($ticket->spot_label ?? ''),
            'entry_time' => $ticket->entry_time?->toIso8601String(),
            'status' => (string) ($ticket->status ?? self::STATUS_UNPAID),
            'scan_count' => (int) ($ticket->scan_count ?? 0),
            'reservation_id' => (string) ($ticket->reservation_id ?? ''),
            'session_id' => (string) ($ticket->session_id ?? ''),
            'paid_at' => $ticket->paid_at?->toIso8601String(),
            'closed_at' => $ticket->closed_at?->toIso8601String(),
            'last_scanned_at' => $ticket->last_scanned_at?->toIso8601String(),
        ];
    }

    private function ticketResponsePayload(ParkingTicket $ticket): array
    {
        $session = null;
        if ((string) ($ticket->session_id ?? '') !== '') {
            $session = ParkingSession::query()->find((string) $ticket->session_id);
        }

        return [
            'ticket' => $this->transformTicket($ticket),
            'parking_session' => $session ? [
                'id' => (string) $session->getKey(),
                'ticket_code' => (string) ($session->ticket_code ?? ''),
                'status' => (string) ($session->status ?? ''),
                'started_at' => $session->started_at?->toIso8601String(),
                'ended_at' => $session->ended_at?->toIso8601String(),
            ] : null,
        ];
    }

    private function buildQrPayload(ParkingTicket $ticket): array
    {
        return [
            'ticket_id' => (string) $ticket->getKey(),
            'ticket_code' => (string) ($ticket->ticket_code ?? ''),
            'parking_id' => (string) ($ticket->parking_id ?? ''),
            'spot_label' => (string) ($ticket->spot_label ?? ''),
            'entry_time' => $ticket->entry_time?->toIso8601String(),
            'status' => (string) ($ticket->status ?? self::STATUS_UNPAID),
        ];
    }
}
