<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\LoginRequest;
use App\Http\Requests\Auth\RegisterUserRequest;
use App\Http\Requests\Auth\UpdateUserProfileRequest;
use App\Models\User;
use App\Services\Auth\AuthService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

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
        $matricule = (string) $request->validated('matricule');
        $email = (string) $request->validated('email');
        $password = (string) $request->validated('password');

        /** @var User|null $user */
        $user = User::query()->where('email', $email)->first();

        if (! $user) {
            return response()->json([
                'message' => 'Email introuvable.',
                'errors' => [
                    'email' => ['Cet email est introuvable.'],
                ],
            ], 401);
        }

        if ($this->normalizeMatricule($matricule) !== $this->normalizeMatricule((string) $user->matricule)) {
            return response()->json([
                'message' => 'Matricule incorrect.',
                'errors' => [
                    'matricule' => ['Ce matricule ne correspond pas a ce compte.'],
                ],
            ], 401);
        }

        if (! Hash::check($password, (string) $user->password)) {
            return response()->json([
                'message' => 'Mot de passe incorrect.',
                'errors' => [
                    'password' => ['Mot de passe incorrect.'],
                ],
            ], 401);
        }

        $token = $user->createToken('user-auth-token')->plainTextToken;

        return response()->json([
            'message' => 'User logged in successfully.',
            'data' => [
                'user' => $user,
                'token' => $token,
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
        /** @var \App\Models\User $user */
        $user = $request->user('user');

        return response()->json([
            'message' => 'User profile retrieved successfully.',
            'data' => $this->toProfilePayload($user),
        ]);
    }

    public function updateProfile(UpdateUserProfileRequest $request): JsonResponse
    {
        /** @var \App\Models\User $user */
        $user = $request->user('user');

        $payload = $request->validated();
        $user->fill($payload);
        $user->save();

        $freshUser = $user->fresh();
        if ($freshUser instanceof User) {
            $user = $freshUser;
        }

        return response()->json([
            'message' => 'User profile updated successfully.',
            'data' => $this->toProfilePayload($user),
        ]);
    }

    private function toProfilePayload(User $user): array
    {
        return [
            'id' => (string) $user->getKey(),
            'name' => $user->name,
            'email' => $user->email,
            'phone' => $user->phone,
            'matricule' => $user->matricule,
            'city' => $user->city,
            'address' => $user->address,
            'latitude' => $user->latitude,
            'longitude' => $user->longitude,
            'avatar_data_url' => $user->avatar_data_url,
        ];
    }

    private function normalizeMatricule(string $value): string
    {
        $upper = strtoupper(trim($value));

        return preg_replace('/[^A-Z0-9]/', '', $upper) ?? $upper;
    }
}
