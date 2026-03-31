<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class Reservation extends Model
{
    protected $connection = 'mongodb';

    protected $collection = 'reservations';

    protected $fillable = [
        'user_id',
        'parking_name',
        'parking_address',
        'equipments',
        'duration_type',
        'duration_minutes',
        'amount',
        'deposit_required',
        'deposit_amount',
        'reservation_status',
        'payment_status',
        'expires_at',
        'cancelled_at',
    ];

    protected $casts = [
        'equipments' => 'array',
        'amount' => 'float',
        'deposit_required' => 'boolean',
        'deposit_amount' => 'float',
        'duration_minutes' => 'integer',
        'expires_at' => 'datetime',
        'cancelled_at' => 'datetime',
    ];
}
