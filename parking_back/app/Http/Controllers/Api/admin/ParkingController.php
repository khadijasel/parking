<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\UpsertParkingLayoutRequest;
use App\Services\Admin\ParkingService;
use Illuminate\Http\JsonResponse;

class ParkingController extends Controller
{
    public function __construct(private readonly ParkingService $parkingService)
    {
    }

    public function index(): JsonResponse
    {
        $items = $this->parkingService->listLayouts()
            ->map(fn ($parking): array => $this->parkingService->toLayoutPayload($parking))
            ->values();

        return response()->json([
            'message' => 'Parkings retrieved successfully.',
            'data' => $items,
        ]);
    }

    public function show(string $parkingId): JsonResponse
    {
        $parking = $this->parkingService->findByParkingId($parkingId);

        if (! $parking) {
            return response()->json([
                'message' => 'Parking not found.',
            ], 404);
        }

        return response()->json([
            'message' => 'Parking retrieved successfully.',
            'data' => $this->parkingService->toLayoutPayload($parking),
        ]);
    }

    public function upsertLayout(UpsertParkingLayoutRequest $request): JsonResponse
    {
        $result = $this->parkingService->upsertLayout(
            $request->validated(),
            $request->user('admin')
        );

        $statusCode = $result['created'] ? 201 : 200;

        return response()->json([
            'message' => $result['created']
                ? 'Parking layout created successfully.'
                : 'Parking layout updated successfully.',
            'data' => $this->parkingService->toLayoutPayload($result['parking']),
        ], $statusCode);
    }

    public function destroy(string $parkingId): JsonResponse
    {
        $deleted = $this->parkingService->deleteByParkingId($parkingId);

        if (! $deleted) {
            return response()->json([
                'message' => 'Parking not found.',
            ], 404);
        }

        return response()->json([
            'message' => 'Parking deleted successfully.',
        ]);
    }
}
