<?php

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

class Parking extends Model
{
    protected $connection = 'mongodb';

    protected $collection = 'parkings';

    protected $fillable = [
        'parking_id',
        'name',
        'address',
        'owner_account',
        'location',
        'capacity',
        'walking_time',
        'rating',
        'price_per_hour',
        'available_spots',
        'last_update',
        'is_open_24h',
        'equipments',
        'tags',
        'image_url',
        'max_vehicle_height_meters',
        'supported_vehicle_types',
        'near_telepherique',
        'indoor_map',
        'working_days',
        'opening_time',
        'closing_time',
        'pricing',
        'business_settings',
        'created_by_admin_id',
        'updated_by_admin_id',
        'updated_by_owner_id',
    ];

    protected $casts = [
        'owner_account' => 'array',
        'location' => 'array',
        'capacity' => 'integer',
        'rating' => 'float',
        'price_per_hour' => 'float',
        'available_spots' => 'integer',
        'is_open_24h' => 'boolean',
        'equipments' => 'array',
        'tags' => 'array',
        'max_vehicle_height_meters' => 'float',
        'supported_vehicle_types' => 'array',
        'near_telepherique' => 'boolean',
        'indoor_map' => 'array',
        'working_days' => 'array',
        'pricing' => 'array',
        'business_settings' => 'array',
    ];
}
