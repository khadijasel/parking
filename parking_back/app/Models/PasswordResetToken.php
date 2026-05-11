<?php

namespace App\Models;

use Illuminate\Support\Facades\Hash;
use MongoDB\Laravel\Eloquent\Model;

class PasswordResetToken extends Model
{
    protected $connection = 'mongodb';
    protected $collection = 'password_reset_tokens';

    public $timestamps = false;

    protected $fillable = [
        'email',
        'token',
        'created_at',
    ];

    protected function casts(): array
    {
        return [
            'created_at' => 'datetime',
        ];
    }

    public function isExpired(): bool
    {
        return $this->created_at === null
            || $this->created_at->lt(now()->subMinutes(60));
    }

    public static function isThrottled(string $email): bool
    {
        $recent = static::query()
            ->where('email', $email)
            ->orderBy('created_at', 'desc')
            ->first();

        if (! $recent instanceof static) {
            return false;
        }

        return $recent->created_at !== null
            && $recent->created_at->gt(now()->subSeconds(60));
    }

    public static function createForEmail(string $email, string $plainCode): static
    {
        /** @var static $record */
        $record = static::query()->create([
            'email'      => $email,
            'token'      => Hash::make($plainCode),
            'created_at' => now(),
        ]);

        return $record;
    }
}
