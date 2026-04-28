<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\GoogleAuthRequest;
use App\Http\Requests\Auth\LoginRequest;
use App\Http\Requests\Auth\RegisterUserRequest;
use App\Http\Requests\Auth\UpdateUserProfileRequest;
use App\Models\User;
use App\Services\Auth\AuthService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Throwable;

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

    public function google(GoogleAuthRequest $request): JsonResponse
    {
        $idToken = trim((string) $request->validated('id_token', ''));
        $accessToken = trim((string) $request->validated('access_token', ''));
        $verification = $this->verifyGoogleToken($idToken, $accessToken);

        if (! $verification['ok']) {
            return response()->json([
                'message' => $verification['message'],
            ], $verification['status']);
        }

        $payload = $verification['payload'];
        $email = strtolower(trim((string) ($payload['email'] ?? '')));
        $name = trim((string) ($payload['name'] ?? ''));
        $picture = trim((string) ($payload['picture'] ?? ''));

        if (! filter_var($email, FILTER_VALIDATE_EMAIL)) {
            return response()->json([
                'message' => 'Google account email is invalid.',
            ], 401);
        }

        /** @var User|null $user */
        $user = User::query()->where('email', $email)->first();
        $isNewUser = false;

        if (! $user) {
            /** @var User $user */
            $user = User::query()->create([
                'name' => $name !== '' ? $name : 'Utilisateur Google',
                'email' => $email,
                'phone' => '',
                'password' => Str::password(40),
                'avatar_data_url' => $picture !== '' ? $picture : null,
            ]);

            $isNewUser = true;
        } else {
            $updates = [];

            if ($name !== '' && trim((string) $user->name) === '') {
                $updates['name'] = $name;
            }

            if ($picture !== '' && trim((string) $user->avatar_data_url) === '') {
                $updates['avatar_data_url'] = $picture;
            }

            if (! empty($updates)) {
                $user->forceFill($updates)->save();
            }
        }

        $user->forceFill([
            'last_login_at' => now(),
        ])->save();

        $token = $user->createToken('user-auth-token')->plainTextToken;

        return response()->json([
            'message' => $isNewUser
                ? 'User registered with Google successfully.'
                : 'User logged in with Google successfully.',
            'data' => [
                'user' => $user,
                'token' => $token,
                'token_type' => 'Bearer',
            ],
        ], $isNewUser ? 201 : 200);
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

    private function verifyGoogleToken(string $idToken, string $accessToken): array
    {
        $attempts = [];

        // Access token is generally more resilient in mobile flows.
        if ($accessToken !== '') {
            $attempts[] = fn (): array => $this->verifyGoogleAccessToken($accessToken);
        }

        if ($idToken !== '') {
            $attempts[] = fn (): array => $this->verifyGoogleIdToken($idToken);
        }

        if (! count($attempts)) {
            return [
                'ok' => false,
                'status' => 422,
                'message' => 'Google token is required.',
                'payload' => [],
            ];
        }

        $lastClientFailure = null;
        $lastServerFailure = null;

        foreach ($attempts as $attempt) {
            $result = $attempt();

            if (($result['ok'] ?? false) === true) {
                return $result;
            }

            $status = (int) ($result['status'] ?? 0);

            if ($status >= 500) {
                $lastServerFailure = $result;
                continue;
            }

            $lastClientFailure = $result;
        }

        return $lastClientFailure
            ?? $lastServerFailure
            ?? [
                'ok' => false,
                'status' => 503,
                'message' => 'Google authentication is temporarily unavailable.',
                'payload' => [],
            ];
    }

    private function verifyGoogleIdToken(string $idToken): array
    {
        try {
            $response = $this->googleHttpClient()
                ->get('https://oauth2.googleapis.com/tokeninfo', [
                    'id_token' => $idToken,
                ]);
        } catch (Throwable $exception) {
            $this->logGoogleTransportException('tokeninfo', $exception);

            return [
                'ok' => false,
                'status' => 503,
                'message' => 'Google authentication is temporarily unavailable.',
                'payload' => [],
            ];
        }

        if ($response->serverError()) {
            return [
                'ok' => false,
                'status' => 503,
                'message' => 'Google authentication is temporarily unavailable.',
                'payload' => [],
            ];
        }

        if ($response->clientError()) {
            return [
                'ok' => false,
                'status' => 401,
                'message' => 'Google token is invalid or expired.',
                'payload' => [],
            ];
        }

        $payload = $response->json();

        if (! is_array($payload)) {
            return [
                'ok' => false,
                'status' => 401,
                'message' => 'Google token payload is invalid.',
                'payload' => [],
            ];
        }

        $email = (string) ($payload['email'] ?? '');
        $isEmailVerified = filter_var(
            (string) ($payload['email_verified'] ?? ''),
            FILTER_VALIDATE_BOOLEAN,
            FILTER_NULL_ON_FAILURE
        ) === true;

        if ($email === '' || ! $isEmailVerified) {
            return [
                'ok' => false,
                'status' => 401,
                'message' => 'Google account email is not verified.',
                'payload' => [],
            ];
        }

        $configuredClientId = trim((string) config('services.google.client_id', ''));
        $tokenAudience = trim((string) ($payload['aud'] ?? ''));

        if ($configuredClientId !== '' && $tokenAudience !== $configuredClientId) {
            return [
                'ok' => false,
                'status' => 401,
                'message' => 'Google token audience is invalid.',
                'payload' => [],
            ];
        }

        return [
            'ok' => true,
            'status' => 200,
            'message' => '',
            'payload' => $payload,
        ];
    }

    private function verifyGoogleAccessToken(string $accessToken): array
    {
        try {
            $response = $this->googleHttpClient()
                ->withToken($accessToken)
                ->get('https://www.googleapis.com/oauth2/v3/userinfo');
        } catch (Throwable $exception) {
            $this->logGoogleTransportException('userinfo', $exception);

            return [
                'ok' => false,
                'status' => 503,
                'message' => 'Google authentication is temporarily unavailable.',
                'payload' => [],
            ];
        }

        if ($response->serverError()) {
            return [
                'ok' => false,
                'status' => 503,
                'message' => 'Google authentication is temporarily unavailable.',
                'payload' => [],
            ];
        }

        if ($response->clientError()) {
            return [
                'ok' => false,
                'status' => 401,
                'message' => 'Google token is invalid or expired.',
                'payload' => [],
            ];
        }

        $payload = $response->json();

        if (! is_array($payload)) {
            return [
                'ok' => false,
                'status' => 401,
                'message' => 'Google token payload is invalid.',
                'payload' => [],
            ];
        }

        $email = (string) ($payload['email'] ?? '');
        $isEmailVerified = filter_var(
            (string) ($payload['email_verified'] ?? ''),
            FILTER_VALIDATE_BOOLEAN,
            FILTER_NULL_ON_FAILURE
        ) === true;

        if ($email === '' || ! $isEmailVerified) {
            return [
                'ok' => false,
                'status' => 401,
                'message' => 'Google account email is not verified.',
                'payload' => [],
            ];
        }

        return [
            'ok' => true,
            'status' => 200,
            'message' => '',
            'payload' => $payload,
        ];
    }

    private function logGoogleTransportException(string $endpoint, Throwable $exception): void
    {
        Log::warning('Google auth transport failure', [
            'endpoint' => $endpoint,
            'exception_class' => $exception::class,
            'message' => $exception->getMessage(),
        ]);
    }

    private function googleHttpClient(): \Illuminate\Http\Client\PendingRequest
    {
        $client = Http::acceptJson()->timeout(12);

        $caBundle = trim((string) config('services.google.ca_bundle', ''));
        if ($caBundle !== '' && is_file($caBundle)) {
            return $client->withOptions([
                'verify' => $caBundle,
            ]);
        }

        $verifySetting = config('services.google.verify_ssl', true);
        $verifySsl = filter_var(
            is_bool($verifySetting) ? ($verifySetting ? 'true' : 'false') : (string) $verifySetting,
            FILTER_VALIDATE_BOOLEAN,
            FILTER_NULL_ON_FAILURE
        );

        if ($verifySsl === false) {
            return $client->withOptions([
                'verify' => false,
            ]);
        }

        return $client;
    }
}
