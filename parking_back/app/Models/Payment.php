<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class Payment extends Model
{
    protected $connection = 'mongodb';

    protected $collection = 'payments';

    protected $fillable = [
        'user_id',
        'reservation_id',
        'parking_name',
        'duration_minutes',
        'amount',
        'method',
        'status',
        'transaction_ref',
        'pin_attempts',
        'remaining_attempts',
        'error_code',
        'error_message',
        'paid_at',
    ];

    protected $casts = [
        'amount' => 'float',
        'duration_minutes' => 'integer',
        'pin_attempts' => 'integer',
        'remaining_attempts' => 'integer',
        'paid_at' => 'datetime',
    ];
}
