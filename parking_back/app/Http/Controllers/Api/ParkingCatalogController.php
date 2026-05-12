<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Parking\ParkingCatalogService;
use Illuminate\Http\JsonResponse;

class ParkingCatalogController extends Controller
{
    public function __construct(private readonly ParkingCatalogService $catalogService)
    {
    }

    public function index(): JsonResponse
    {
        $items = $this->catalogService->list()
            ->map(fn ($parking): array => $this->catalogService->toPublicPayload($parking))
            ->values();

        return response()->json([
            'message' => 'Parkings retrieved successfully.',
            'data' => $items,
        ]);
    }

    public function spots(string $parkingId): JsonResponse
    {
        $parking = $this->catalogService->findById($parkingId);

        if (! $parking) {
            return response()->json(['message' => 'Parking not found.'], 404);
        }

        return response()->json([
            'message' => 'Spots retrieved successfully.',
            'data' => $this->catalogService->spotsPayload($parking),
        ]);
    }
}
