<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\UpdateOwnerStatusRequest;
use App\Services\Admin\UserManagementService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class UserManagementController extends Controller
{
    public function __construct(private readonly UserManagementService $userManagementService)
    {
    }

    public function index(): JsonResponse
    {
        $users = $this->userManagementService->listUsers();

        return response()->json([
            'message' => 'Users retrieved successfully.',
            'data' => [
                'users' => $users,
                'totals' => $this->userManagementService->summarizeUsers($users),
            ],
        ]);
    }

    public function updateOwnerStatus(UpdateOwnerStatusRequest $request, string $ownerId): JsonResponse
    {
        $validated = $request->validated();

        $owner = $this->userManagementService->setOwnerAccountStatus(
            ownerId: $ownerId,
            accountStatus: (string) $validated['accountStatus'],
            subscriptionStatus: $validated['subscriptionStatus'] ?? null,
            reason: $validated['reason'] ?? null,
        );

        if (! $owner) {
            return response()->json([
                'message' => 'Owner not found.',
            ], 404);
        }

        return response()->json([
            'message' => 'Owner status updated successfully.',
            'data' => [
                'owner' => $this->userManagementService->toOwnerUserRow($owner),
            ],
        ]);
    }

    public function history(Request $request): JsonResponse
    {
        $limit = (int) $request->query('limit', 120);
        $events = $this->userManagementService->listGlobalHistory($limit);

        return response()->json([
            'message' => 'Global history retrieved successfully.',
            'data' => [
                'events' => $events,
            ],
        ]);
    }
}
