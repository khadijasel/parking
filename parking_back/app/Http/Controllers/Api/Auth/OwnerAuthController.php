<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\ActorLoginRequest;
use App\Models\ParkingOwner;
use App\Services\Auth\AuthService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Throwable;

class OwnerAuthController extends Controller
{
    public function __construct(private readonly AuthService $authService)
    {
    }

    public function login(ActorLoginRequest $request): JsonResponse
    {
        try {
            $email = (string) $request->validated('email');
            $password = (string) $request->validated('password');

            /** @var ParkingOwner|null $owner */
            $owner = ParkingOwner::query()->where('email', $email)->first();

            if (! $owner || ! Hash::check($password, (string) $owner->password)) {
                return response()->json([
                    'message' => 'Invalid credentials.',
                    'errors' => [
                        'email' => ['The provided credentials are incorrect.'],
                    ],
                ], 401);
            }

            $accountStatus = strtolower((string) ($owner->account_status ?? 'active'));
            if ($accountStatus === 'blocked') {
                return response()->json([
                    'message' => 'Owner account is suspended. Please contact admin to renew subscription.',
                ], 403);
            }

            $owner->forceFill([
                'last_login_at' => now(),
            ])->save();

            $token = $owner->createToken('owner-auth-token')->plainTextToken;

            return response()->json([
                'message' => 'Owner logged in successfully.',
                'data' => [
                    'owner' => $owner,
                    'token' => $token,
                    'token_type' => 'Bearer',
                ],
            ]);
        } catch (Throwable) {
            return response()->json([
                'message' => 'Service temporairement indisponible. Veuillez reessayer.',
            ], 503);
        }
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
