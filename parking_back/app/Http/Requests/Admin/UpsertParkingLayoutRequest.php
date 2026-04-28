<?php

namespace App\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpsertParkingLayoutRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'parkingId' => ['required', 'string', 'max:60'],
            'name' => ['required', 'string', 'max:150'],
            'address' => ['required', 'string', 'max:255'],
            'ownerAccount' => ['required', 'array'],
            'ownerAccount.name' => ['required', 'string', 'max:255'],
            'ownerAccount.email' => ['required', 'email', 'max:255'],
            'ownerAccount.phone' => ['nullable', 'string', 'max:40'],
            'location' => ['required', 'array'],
            'location.lat' => ['required', 'numeric', 'between:-90,90'],
            'location.lng' => ['required', 'numeric', 'between:-180,180'],
            'capacity' => ['required', 'integer', 'min:1'],
            'walkingTime' => ['nullable', 'string', 'max:120'],
            'rating' => ['nullable', 'numeric', 'between:0,5'],
            'pricePerHour' => ['nullable', 'numeric', 'min:0'],
            'availableSpots' => ['nullable', 'integer', 'min:0'],
            'lastUpdate' => ['nullable', 'string', 'max:120'],
            'isOpen24h' => ['nullable', 'boolean'],
            'equipments' => ['nullable', 'array'],
            'equipments.*' => ['string', 'max:120'],
            'tags' => ['nullable', 'array'],
            'tags.*' => ['string', 'max:120'],
            'imageUrl' => ['nullable', 'string', 'max:7340032'],
            'maxVehicleHeightMeters' => ['nullable', 'numeric', 'min:0'],
            'supportedVehicleTypes' => ['nullable', 'array'],
            'supportedVehicleTypes.*' => ['string', 'max:50'],
            'nearTelepherique' => ['nullable', 'boolean'],
            'indoorMap' => ['required', 'array'],
            'indoorMap.floor' => ['required', 'string', 'max:60'],
            'indoorMap.zone' => ['required', 'string', 'max:60'],
            'indoorMap.grid' => ['required', 'array'],
            'indoorMap.grid.rows' => ['required', 'integer', 'min:1'],
            'indoorMap.grid.cols' => ['required', 'integer', 'min:1'],
            'indoorMap.grid.laneRows' => ['nullable', 'array'],
            'indoorMap.grid.laneRows.*' => ['integer', 'min:0'],
            'indoorMap.spots' => ['nullable', 'array'],
            'indoorMap.spots.*.spotId' => ['required', 'string', 'max:80'],
            'indoorMap.spots.*.label' => ['required', 'string', 'max:80'],
            'indoorMap.spots.*.row' => ['required', 'integer', 'min:0'],
            'indoorMap.spots.*.col' => ['required', 'integer', 'min:0'],
            'indoorMap.spots.*.type' => ['required', Rule::in(['STANDARD', 'PMR', 'VIP'])],
            'indoorMap.spots.*.state' => ['required', Rule::in(['AVAILABLE', 'OCCUPIED', 'RESERVED', 'OFFLINE'])],
            'indoorMap.spots.*.sensor' => ['nullable', 'array'],
            'indoorMap.spots.*.sensor.arduinoId' => ['nullable', 'string', 'max:120'],
            'indoorMap.spots.*.sensor.channel' => ['nullable', 'string', 'max:120'],
            'indoorMap.spots.*.sensor.topic' => ['nullable', 'string', 'max:255'],
            'indoorMap.spots.*.updatedAt' => ['nullable', 'date'],
        ];
    }
}
