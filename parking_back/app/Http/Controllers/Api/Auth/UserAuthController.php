<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\LoginRequest;
use App\Http\Requests\Auth\RegisterUserRequest;
use App\Models\User;
use App\Services\Auth\AuthService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class UserAuthController extends Controller
{
    public function __construct(private readonly AuthService $authService)
    {
    }

    public function register(RegisterUserRequest $request): JsonResponse
    {
        $user = $this->authService->register(User::class, $request->validated());
        $token = $user->createToken('user-auth-token')->plainTextToken;

        return response()->json([
            'message' => 'User registered successfully.',
            'data' => [
                'user' => $user,
                'token' => $token,
                'token_type' => 'Bearer',
            ],
        ], 201);
    }

    public function login(LoginRequest $request): JsonResponse
    {
        $result = $this->authService->login(
            User::class,
            (string) $request->validated('email'),
            (string) $request->validated('password'),
            'user-auth-token'
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
            'message' => 'User logged in successfully.',
            'data' => [
                'user' => $result['actor'],
                'token' => $result['token'],
                'token_type' => 'Bearer',
            ],
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        /** @var \App\Models\User $user */
        $user = $request->user('user');
        $this->authService->logout($user);

        return response()->json([
            'message' => 'User logged out successfully.',
        ]);
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json([
            'message' => 'User profile retrieved successfully.',
            'data' => $request->user('user'),
        ]);
    }
}
