<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;
use MongoDB\Laravel\Auth\User as Authenticatable;

class ParkingOwner extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable;

    protected $connection = 'mongodb';

    protected $collection = 'parking_owners';

    protected $fillable = [
        'name',
        'email',
        'phone',
        'password',
        'account_status',
        'subscription_status',
        'subscription_ends_at',
        'blocked_at',
        'blocked_reason',
        'last_login_at',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'password' => 'hashed',
            'subscription_ends_at' => 'datetime',
            'blocked_at' => 'datetime',
            'last_login_at' => 'datetime',
        ];
    }
}
