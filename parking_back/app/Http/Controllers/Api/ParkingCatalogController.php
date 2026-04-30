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
}
