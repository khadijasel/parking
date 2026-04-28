<?php

namespace App\Services\Auth;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Hash;

class AuthService
{
    public function login(string $modelClass, string $email, string $password, string $tokenName): ?array
    {
        /** @var \Illuminate\Database\Eloquent\Model|null $actor */
        $actor = $modelClass::query()->where('email', $email)->first();

        if (! $actor || ! Hash::check($password, (string) $actor->password)) {
            return null;
        }

        $actor->forceFill([
            'last_login_at' => now(),
        ])->save();

        $token = $actor->createToken($tokenName)->plainTextToken;

        return [
            'actor' => $actor,
            'token' => $token,
        ];
    }

    public function register(string $modelClass, array $payload): Model
    {
        $payload['password'] = Hash::make((string) $payload['password']);

        /** @var \Illuminate\Database\Eloquent\Model $actor */
        $actor = $modelClass::query()->create($payload);

        return $actor;
    }

    public function logout(Model $actor): void
    {
        $token = $actor->currentAccessToken();

        if ($token) {
            $token->delete();
            return;
        }

        $actor->tokens()->delete();
    }
}
