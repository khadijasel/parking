<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class ParkingSession extends Model
{
    protected $connection = 'mongodb';

    protected $collection = 'parking_sessions';

    protected $fillable = [
        'user_id',
        'reservation_id',
        'parking_name',
        'parking_address',
        'ticket_code',
        'status',
        'started_at',
        'ended_at',
    ];

    protected $casts = [
        'started_at' => 'datetime',
        'ended_at' => 'datetime',
    ];
}
