<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Parking\InfraredSensorReadingsRequest;
use App\Services\Parking\ParkingAvailabilityService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ParkingAvailabilityController extends Controller
{
    public function __construct(private readonly ParkingAvailabilityService $availabilityService)
    {
    }

    public function index(): JsonResponse
    {
        return response()->json([
            'message' => 'Parking availability retrieved successfully.',
            'data' => $this->availabilityService->list(),
        ]);
    }

    public function updateArduino(Request $request): JsonResponse
    {
        $authorizationResponse = $this->authorizeSensorUpdate($request);
        if ($authorizationResponse !== null) {
            return $authorizationResponse;
        }

        $payload = $request->validate([
            'available_spots' => ['required', 'integer', 'min:0'],
            'total_spots' => ['nullable', 'integer', 'min:1'],
        ]);

        $updated = $this->availabilityService->updateArduinoAvailability(
            (int) $payload['available_spots'],
            isset($payload['total_spots']) ? (int) $payload['total_spots'] : null,
        );

        return response()->json([
            'message' => 'Arduino parking availability updated successfully.',
            'data' => $updated,
        ]);
    }

    public function updateInfraredReadings(InfraredSensorReadingsRequest $request): JsonResponse
    {
        $authorizationResponse = $this->authorizeSensorUpdate($request);
        if ($authorizationResponse !== null) {
            return $authorizationResponse;
        }

        $payload = $request->validated();
        $sentAt = isset($payload['sent_at']) && trim((string) $payload['sent_at']) !== ''
            ? CarbonImmutable::parse((string) $payload['sent_at'])
            : null;

        try {
            $updated = $this->availabilityService->updateInfraredReadings(
                (string) $payload['parking_id'],
                (array) ($payload['readings'] ?? []),
                isset($payload['device_id']) ? (string) $payload['device_id'] : null,
                $sentAt,
            );
        } catch (\RuntimeException $exception) {
            return response()->json([
                'message' => $exception->getMessage(),
            ], 422);
        }

        if (! $updated) {
            return response()->json([
                'message' => 'Parking not found.',
            ], 404);
        }

        return response()->json([
            'message' => 'Infrared sensor readings processed successfully.',
            'data' => $updated,
        ]);
    }

    private function authorizeSensorUpdate(Request $request): ?JsonResponse
    {
        $allowedKeys = collect([
            trim((string) config('services.infrared.key', '')),
            trim((string) config('services.arduino.key', '')),
        ])
            ->filter(fn (string $key): bool => $key !== '')
            ->unique()
            ->values()
            ->all();

        if (! count($allowedKeys)) {
            return null;
        }

        $sensorKey = trim((string) $request->header('X-Sensor-Key', ''));
        $arduinoKey = trim((string) $request->header('X-Arduino-Key', ''));

        if (
            ($sensorKey !== '' && in_array($sensorKey, $allowedKeys, true))
            || ($arduinoKey !== '' && in_array($arduinoKey, $allowedKeys, true))
        ) {
            return null;
        }

        return response()->json([
            'message' => 'Unauthorized sensor update.',
        ], 401);
    }
}
