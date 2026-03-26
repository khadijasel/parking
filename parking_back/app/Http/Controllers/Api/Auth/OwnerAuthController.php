<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\LoginRequest;
use App\Models\ParkingOwner;
use App\Services\Auth\AuthService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class OwnerAuthController extends Controller
{
    public function __construct(private readonly AuthService $authService)
    {
    }

    public function login(LoginRequest $request): JsonResponse
    {
        $result = $this->authService->login(
            ParkingOwner::class,
            (string) $request->validated('email'),
            (string) $request->validated('password'),
            'owner-auth-token'
        );

        if (! $result) {
            return response()->json([
                'message' => 'Invalid credentials.',
                'errors' => [
                    'email' => ['The provided credentials are incorrect.'],
                ],
            ], 401);
        }

        return response()->json([
            'message' => 'Owner logged in successfully.',
            'data' => [
                'owner' => $result['actor'],
                'token' => $result['token'],
                'token_type' => 'Bearer',
            ],
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        /** @var \App\Models\ParkingOwner $owner */
        $owner = $request->user('owner');
        $this->authService->logout($owner);

        return response()->json([
            'message' => 'Owner logged out successfully.',
        ]);
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json([
            'message' => 'Owner profile retrieved successfully.',
            'data' => $request->user('owner'),
        ]);
    }
}
