<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\ActorLoginRequest;
use App\Http\Requests\Auth\CreateParkingOwnerRequest;
use App\Models\Admin;
use App\Models\ParkingOwner;
use App\Services\Auth\AuthService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Throwable;

class AdminAuthController extends Controller
{
    public function __construct(private readonly AuthService $authService)
    {
    }

    public function login(ActorLoginRequest $request): JsonResponse
    {
        try {
            $result = $this->authService->login(
                Admin::class,
                (string) $request->validated('email'),
                (string) $request->validated('password'),
                'admin-auth-token'
            );
        } catch (Throwable) {
            return response()->json([
                'message' => 'Service temporairement indisponible. Veuillez reessayer.',
            ], 503);
        }

        if (! $result) {
            return response()->json([
                'message' => 'Invalid credentials.',
                'errors' => [
                    'email' => ['The provided credentials are incorrect.'],
                ],
            ], 401);
        }

        return response()->json([
            'message' => 'Admin logged in successfully.',
            'data' => [
                'admin' => $result['actor'],
                'token' => $result['token'],
                'token_type' => 'Bearer',
            ],
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        /** @var \App\Models\Admin $admin */
        $admin = $request->user('admin');
        $this->authService->logout($admin);

        return response()->json([
            'message' => 'Admin logged out successfully.',
        ]);
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json([
            'message' => 'Admin profile retrieved successfully.',
            'data' => $request->user('admin'),
        ]);
    }

    public function createOwner(CreateParkingOwnerRequest $request): JsonResponse
    {
        $owner = $this->authService->register(ParkingOwner::class, [
            ...$request->validated(),
            'account_status' => 'active',
            'subscription_status' => 'active',
            'subscription_ends_at' => null,
            'blocked_at' => null,
            'blocked_reason' => null,
        ]);

        return response()->json([
            'message' => 'Parking owner account created successfully.',
            'data' => $owner,
        ], 201);
    }
}
