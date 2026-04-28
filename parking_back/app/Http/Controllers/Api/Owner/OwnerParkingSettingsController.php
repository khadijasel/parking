<?php

namespace App\Http\Controllers\Api\Owner;

use App\Http\Controllers\Controller;
use App\Http\Requests\Owner\UpdateBusinessSettingsRequest;
use App\Models\ParkingOwner;
use App\Services\Owner\OwnerParkingSettingsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class OwnerParkingSettingsController extends Controller
{
    public function __construct(private readonly OwnerParkingSettingsService $ownerParkingSettingsService)
    {
    }

    public function index(Request $request): JsonResponse
    {
        /** @var ParkingOwner $owner */
        $owner = $request->user('owner');

        $items = $this->ownerParkingSettingsService
            ->listForOwner($owner)
            ->map(fn ($parking): array => $this->ownerParkingSettingsService->toOwnerPayload($parking))
            ->values();

        return response()->json([
            'message' => 'Owner parkings retrieved successfully.',
            'data' => $items,
        ]);
    }

    public function updateBusinessSettings(
        UpdateBusinessSettingsRequest $request,
        string $parkingId
    ): JsonResponse {
        /** @var ParkingOwner $owner */
        $owner = $request->user('owner');

        $parking = $this->ownerParkingSettingsService->findForOwner($owner, $parkingId);

        if (! $parking) {
            return response()->json([
                'message' => 'Parking not found for this owner.',
            ], 404);
        }

        $updated = $this->ownerParkingSettingsService->updateBusinessSettings(
            $parking,
            $owner,
            $request->validated()
        );

        return response()->json([
            'message' => 'Business settings updated successfully.',
            'data' => $this->ownerParkingSettingsService->toOwnerPayload($updated),
        ]);
    }
}
