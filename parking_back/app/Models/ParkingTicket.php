<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class ParkingTicket extends Model
{
    protected $connection = 'mongodb';

    protected $collection = 'parking_tickets';

    protected $fillable = [
        'ticket_code',
        'parking_id',
        'parking_name',
        'entry_time',
        'status',
        'user_id',
        'reservation_id',
        'session_id',
        'scan_count',
        'last_scanned_at',
        'paid_at',
        'closed_at',
    ];

    protected $casts = [
        'entry_time' => 'datetime',
        'scan_count' => 'integer',
        'last_scanned_at' => 'datetime',
        'paid_at' => 'datetime',
        'closed_at' => 'datetime',
    ];
}
