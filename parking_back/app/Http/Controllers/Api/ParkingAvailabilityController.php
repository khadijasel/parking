<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Parking\ParkingAvailabilityService;
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
        $expectedKey = (string) config('services.arduino.key', '');
        $providedKey = (string) $request->header('X-Arduino-Key', '');

        if ($expectedKey !== '' && $providedKey !== $expectedKey) {
            return response()->json([
                'message' => 'Unauthorized Arduino update.',
            ], 401);
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
}
