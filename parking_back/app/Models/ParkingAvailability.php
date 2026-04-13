<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class ParkingAvailability extends Model
{
    protected $connection = 'mongodb';

    protected $collection = 'parking_availabilities';

    protected $fillable = [
        'parking_id',
        'parking_name',
        'total_spots',
        'available_spots',
        'is_arduino',
        'last_sensor_at',
    ];

    protected $casts = [
        'total_spots' => 'integer',
        'available_spots' => 'integer',
        'is_arduino' => 'boolean',
        'last_sensor_at' => 'datetime',
    ];
}
