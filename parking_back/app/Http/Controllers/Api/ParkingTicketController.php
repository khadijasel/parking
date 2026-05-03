<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Parking;
use App\Models\ParkingSession;
use App\Models\ParkingTicket;
use App\Models\Reservation;
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
        ]);

        $parkingId = trim((string) $payload['parking_id']);
        $parkingName = trim((string) ($payload['parking_name'] ?? ''));

        $parking = $this->resolveParkingRecord($parkingId, $parkingName);
        if ($parking instanceof Parking) {
            $parkingId = $this->resolveParkingId($parking);
            $parkingName = trim((string) ($parking->name ?? $parkingName));
        }

        $ticketCode = $this->generateTicketCode($parkingName);
        $entryTime = isset($payload['entry_time'])
            ? CarbonImmutable::parse($payload['entry_time'])
            : CarbonImmutable::now();

        $ticket = ParkingTicket::query()->create([
            'ticket_code' => $ticketCode,
            'parking_id' => $parkingId,
            'parking_name' => $parkingName,
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
                $ticket->reservation_id = (string) $reservation->getKey();
                $ticket->parking_id = (string) ($reservation->parking_id ?? $ticket->parking_id);
                $ticket->parking_name = (string) ($reservation->parking_name ?? $ticket->parking_name);

                if ((string) ($reservation->payment_status ?? '') === self::STATUS_PAID) {
                    $ticket->status = self::STATUS_PAID;
                    $ticket->paid_at = $ticket->paid_at ?? CarbonImmutable::now();
                }

                $ticket->ticket_code = $this->buildReservationTicketCode($reservation);

                $session = $this->createSessionFromReservation($reservation, $ticket->ticket_code);
                $ticket->session_id = (string) $session->getKey();
            } else {
                $session = $this->createSessionFromTicket($ticket);
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

    private function generateTicketCode(string $parkingName): string
    {
        $parkingCode = $this->resolveParkingCode($parkingName);
        $random = strtoupper(Str::random(6));

        return $parkingCode.'-'.$random;
    }

    private function buildReservationTicketCode(Reservation $reservation): string
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

    private function resolveSpotLabel(string $parkingName, string $seed): string
    {
        $normalized = strtolower($parkingName);
        if (str_contains($normalized, 'arduino') || str_contains($normalized, 'notre parking')) {
            $spot = $this->stableIndex($seed, 6) + 1;

            return 'A'.$spot;
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

    private function createSessionFromReservation(Reservation $reservation, string $ticketCode): ParkingSession
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
            'status' => self::SESSION_STATUS_ACTIVE,
            'started_at' => $now,
            'ended_at' => null,
        ]);
    }

    private function createSessionFromTicket(ParkingTicket $ticket): ParkingSession
    {
        $now = CarbonImmutable::now();
        $userId = (string) ($ticket->user_id ?? '');

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
        $session->save();
    }

    private function transformTicket(ParkingTicket $ticket): array
    {
        return [
            'id' => (string) $ticket->getKey(),
            'ticket_code' => (string) ($ticket->ticket_code ?? ''),
            'parking_id' => (string) ($ticket->parking_id ?? ''),
            'parking_name' => (string) ($ticket->parking_name ?? ''),
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
            'entry_time' => $ticket->entry_time?->toIso8601String(),
            'status' => (string) ($ticket->status ?? self::STATUS_UNPAID),
        ];
    }
}
