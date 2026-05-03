<?php

namespace App\Services\Parking;

use App\Models\Parking;
use Illuminate\Support\Collection;

class ParkingCatalogService
{
    public function list(): Collection
    {
        return Parking::query()
            ->orderBy('name')
            ->get();
    }

    public function toPublicPayload(Parking $parking): array
    {
        $location = (array) ($parking->location ?? []);
        $indoorMap = (array) ($parking->indoor_map ?? []);
        $grid = (array) ($indoorMap['grid'] ?? []);
        $spots = collect($indoorMap['spots'] ?? [])
            ->map(fn ($spot): array => (array) $spot)
            ->values()
            ->all();

        $availableSpots = $this->resolveAvailableSpots($parking, $spots);
        $pricePerHour = $this->resolvePricePerHour($parking);

        return [
            'parkingId' => $this->resolveParkingId($parking),
            'name' => (string) ($parking->name ?? ''),
            'address' => (string) ($parking->address ?? ''),
            'capacity' => (int) ($parking->capacity ?? 0),
            'walkingTime' => (string) ($parking->walking_time ?? ''),
            'rating' => (float) ($parking->rating ?? 0),
            'pricePerHour' => $pricePerHour,
            'availableSpots' => $availableSpots,
            'lastUpdate' => (string) ($parking->last_update ?? ''),
            'isOpen24h' => (bool) ($parking->is_open_24h ?? false),
            'equipments' => $this->normalizeStringArray($parking->equipments ?? []),
            'tags' => $this->normalizeStringArray($parking->tags ?? []),
            'imageUrl' => (string) ($parking->image_url ?? ''),
            'maxVehicleHeightMeters' => $parking->max_vehicle_height_meters !== null
                ? (float) $parking->max_vehicle_height_meters
                : null,
            'supportedVehicleTypes' => $this->normalizeStringArray($parking->supported_vehicle_types ?? []),
            'nearTelepherique' => (bool) ($parking->near_telepherique ?? false),
            'location' => [
                'lat' => (float) ($location['lat'] ?? 0),
                'lng' => (float) ($location['lng'] ?? 0),
            ],
            'indoorMap' => [
                'floor' => (string) ($indoorMap['floor'] ?? 'B1'),
                'zone' => (string) ($indoorMap['zone'] ?? 'Zone A'),
                'grid' => [
                    'rows' => (int) ($grid['rows'] ?? 0),
                    'cols' => (int) ($grid['cols'] ?? 0),
                    'laneRows' => collect($grid['laneRows'] ?? [])->map(fn ($row): int => (int) $row)->values()->all(),
                    'laneCols' => collect($grid['laneCols'] ?? [])->map(fn ($col): int => (int) $col)->values()->all(),
                ],
                'spots' => $spots,
            ],
        ];
    }

    private function resolveParkingId(Parking $parking): string
    {
        $parkingId = trim((string) ($parking->parking_id ?? ''));

        if ($parkingId !== '') {
            return $parkingId;
        }

        return (string) $parking->getKey();
    }

    private function resolvePricePerHour(Parking $parking): float
    {
        if ($parking->price_per_hour !== null) {
            return (float) $parking->price_per_hour;
        }

        $businessSettings = (array) ($parking->business_settings ?? []);
        $pricing = (array) ($businessSettings['pricing'] ?? ($parking->pricing ?? []));

        if (array_key_exists('hourlyRateDzd', $pricing)) {
            return (float) ($pricing['hourlyRateDzd'] ?? 0);
        }

        if (array_key_exists('hourly_rate_dzd', $pricing)) {
            return (float) ($pricing['hourly_rate_dzd'] ?? 0);
        }

        return 0.0;
    }

    private function resolveAvailableSpots(Parking $parking, array $spots): int
    {
        if ($parking->available_spots !== null) {
            return max(0, (int) $parking->available_spots);
        }

        if (!count($spots)) {
            return max(0, (int) ($parking->capacity ?? 0));
        }

        return max(0, collect($spots)
            ->filter(fn ($spot): bool => strtoupper((string) (($spot['state'] ?? ''))) === 'AVAILABLE')
            ->count());
    }

    /**
     * @return array<int, string>
     */
    private function normalizeStringArray(mixed $value): array
    {
        if (is_string($value)) {
            $value = preg_split('/[\r\n,;]+/', $value) ?: [];
        }

        if ($value instanceof \Traversable) {
            $value = iterator_to_array($value, false);
        }

        if (!is_array($value)) {
            $value = [];
        }

        return collect($value)
            ->map(fn ($item): string => trim((string) $item))
            ->filter(fn (string $item): bool => $item !== '')
            ->values()
            ->all();
    }
}
