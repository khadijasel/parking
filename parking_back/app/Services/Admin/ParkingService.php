<?php

namespace App\Services\Admin;

use App\Models\Parking;
use Illuminate\Contracts\Auth\Authenticatable;
use Illuminate\Support\Collection;

class ParkingService
{
    public function upsertLayout(array $payload, ?Authenticatable $admin = null): array
    {
        $parkingId = (string) $payload['parkingId'];

        /** @var Parking|null $existing */
        $existing = Parking::query()->where('parking_id', $parkingId)->first();
        $isCreated = ! $existing;

        $attributes = $this->toPersistenceAttributes($payload, $admin, $existing);

        if ($existing) {
            $existing->fill($attributes);
            $existing->save();

            return [
                'parking' => $existing,
                'created' => false,
            ];
        }

        /** @var Parking $parking */
        $parking = Parking::query()->create([
            'parking_id' => $parkingId,
            ...$attributes,
        ]);

        return [
            'parking' => $parking,
            'created' => $isCreated,
        ];
    }

    public function findByParkingId(string $parkingId): ?Parking
    {
        /** @var Parking|null $parking */
        $parking = Parking::query()->where('parking_id', $parkingId)->first();

        return $parking;
    }

    public function listLayouts(): Collection
    {
        return Parking::query()
            ->orderByDesc('updated_at')
            ->get();
    }

    public function deleteByParkingId(string $parkingId): bool
    {
        $parking = $this->findByParkingId($parkingId);

        if (! $parking) {
            return false;
        }

        return (bool) $parking->delete();
    }

    public function toLayoutPayload(Parking $parking): array
    {
        $ownerAccount = (array) ($parking->owner_account ?? []);
        $location = (array) ($parking->location ?? []);
        $indoorMap = (array) ($parking->indoor_map ?? []);
        $grid = (array) ($indoorMap['grid'] ?? []);

        $spots = collect($indoorMap['spots'] ?? [])
            ->map(function ($spot): array {
                $spotArray = (array) $spot;
                $sensor = (array) ($spotArray['sensor'] ?? []);

                return [
                    'spotId' => (string) ($spotArray['spotId'] ?? ''),
                    'label' => (string) ($spotArray['label'] ?? ''),
                    'row' => (int) ($spotArray['row'] ?? 0),
                    'col' => (int) ($spotArray['col'] ?? 0),
                    'type' => (string) ($spotArray['type'] ?? 'STANDARD'),
                    'state' => (string) ($spotArray['state'] ?? 'AVAILABLE'),
                    'sensor' => [
                        'arduinoId' => (string) ($sensor['arduinoId'] ?? ''),
                        'channel' => (string) ($sensor['channel'] ?? ''),
                        'topic' => (string) ($sensor['topic'] ?? ''),
                    ],
                    'updatedAt' => (string) ($spotArray['updatedAt'] ?? now()->toIso8601String()),
                ];
            })
            ->values()
            ->all();

        $availableSpots = $this->resolveAvailableSpots($parking, $spots);

        return [
            'parkingId' => (string) ($parking->parking_id ?? $parking->getKey()),
            'name' => (string) ($parking->name ?? ''),
            'address' => (string) ($parking->address ?? ''),
            'ownerAccount' => [
                'name' => (string) ($ownerAccount['name'] ?? ''),
                'email' => (string) ($ownerAccount['email'] ?? ''),
                'phone' => (string) ($ownerAccount['phone'] ?? ''),
            ],
            'location' => [
                'lat' => (float) ($location['lat'] ?? 0),
                'lng' => (float) ($location['lng'] ?? 0),
            ],
            'capacity' => (int) ($parking->capacity ?? 0),
            'walkingTime' => (string) ($parking->walking_time ?? ''),
            'rating' => (float) ($parking->rating ?? 0),
            'pricePerHour' => (float) ($parking->price_per_hour ?? 0),
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
            'indoorMap' => [
                'floor' => (string) ($indoorMap['floor'] ?? 'B1'),
                'zone' => (string) ($indoorMap['zone'] ?? 'Zone A'),
                'grid' => [
                    'rows' => (int) ($grid['rows'] ?? 0),
                    'cols' => (int) ($grid['cols'] ?? 0),
                    'laneRows' => collect($grid['laneRows'] ?? [])->map(fn ($row): int => (int) $row)->values()->all(),
                ],
                'spots' => $spots,
            ],
            'createdAt' => $parking->created_at?->toIso8601String(),
            'updatedAt' => $parking->updated_at?->toIso8601String(),
        ];
    }

    private function toPersistenceAttributes(array $payload, ?Authenticatable $admin, ?Parking $existing = null): array
    {
        $adminId = $admin ? (string) $admin->getAuthIdentifier() : '';

        $equipments = array_key_exists('equipments', $payload)
            ? $this->normalizeStringArray($payload['equipments'] ?? [])
            : $this->normalizeStringArray($existing?->equipments ?? []);

        $tags = array_key_exists('tags', $payload)
            ? $this->normalizeStringArray($payload['tags'] ?? [])
            : $this->normalizeStringArray($existing?->tags ?? []);

        $supportedVehicleTypes = array_key_exists('supportedVehicleTypes', $payload)
            ? $this->normalizeStringArray($payload['supportedVehicleTypes'] ?? [])
            : $this->normalizeStringArray($existing?->supported_vehicle_types ?? []);

        return [
            'name' => (string) $payload['name'],
            'address' => (string) $payload['address'],
            'owner_account' => [
                'name' => (string) ($payload['ownerAccount']['name'] ?? ''),
                'email' => strtolower((string) ($payload['ownerAccount']['email'] ?? '')),
                'phone' => (string) ($payload['ownerAccount']['phone'] ?? ''),
            ],
            'location' => [
                'lat' => (float) ($payload['location']['lat'] ?? 0),
                'lng' => (float) ($payload['location']['lng'] ?? 0),
            ],
            'capacity' => (int) ($payload['capacity'] ?? 0),
            'walking_time' => array_key_exists('walkingTime', $payload)
                ? (string) ($payload['walkingTime'] ?? '')
                : (string) ($existing?->walking_time ?? ''),
            'rating' => array_key_exists('rating', $payload)
                ? ($payload['rating'] === null ? null : (float) $payload['rating'])
                : $existing?->rating,
            'price_per_hour' => array_key_exists('pricePerHour', $payload)
                ? ($payload['pricePerHour'] === null ? null : (float) $payload['pricePerHour'])
                : $existing?->price_per_hour,
            'available_spots' => array_key_exists('availableSpots', $payload)
                ? ($payload['availableSpots'] === null ? null : max(0, (int) $payload['availableSpots']))
                : ($existing?->available_spots ?? null),
            'last_update' => array_key_exists('lastUpdate', $payload)
                ? (string) ($payload['lastUpdate'] ?? '')
                : (string) ($existing?->last_update ?? ''),
            'is_open_24h' => array_key_exists('isOpen24h', $payload)
                ? (bool) ($payload['isOpen24h'] ?? false)
                : (bool) ($existing?->is_open_24h ?? false),
            'equipments' => $equipments,
            'tags' => $tags,
            'image_url' => array_key_exists('imageUrl', $payload)
                ? (string) ($payload['imageUrl'] ?? '')
                : (string) ($existing?->image_url ?? ''),
            'max_vehicle_height_meters' => array_key_exists('maxVehicleHeightMeters', $payload)
                ? ($payload['maxVehicleHeightMeters'] === null ? null : (float) $payload['maxVehicleHeightMeters'])
                : $existing?->max_vehicle_height_meters,
            'supported_vehicle_types' => $supportedVehicleTypes,
            'near_telepherique' => array_key_exists('nearTelepherique', $payload)
                ? (bool) ($payload['nearTelepherique'] ?? false)
                : (bool) ($existing?->near_telepherique ?? false),
            'indoor_map' => [
                'floor' => (string) ($payload['indoorMap']['floor'] ?? 'B1'),
                'zone' => (string) ($payload['indoorMap']['zone'] ?? 'Zone A'),
                'grid' => [
                    'rows' => (int) ($payload['indoorMap']['grid']['rows'] ?? 0),
                    'cols' => (int) ($payload['indoorMap']['grid']['cols'] ?? 0),
                    'laneRows' => collect($payload['indoorMap']['grid']['laneRows'] ?? [])->map(fn ($row): int => (int) $row)->values()->all(),
                ],
                'spots' => collect($payload['indoorMap']['spots'] ?? [])->map(function ($spot): array {
                    return [
                        'spotId' => (string) ($spot['spotId'] ?? ''),
                        'label' => (string) ($spot['label'] ?? ''),
                        'row' => (int) ($spot['row'] ?? 0),
                        'col' => (int) ($spot['col'] ?? 0),
                        'type' => (string) ($spot['type'] ?? 'STANDARD'),
                        'state' => (string) ($spot['state'] ?? 'AVAILABLE'),
                        'sensor' => [
                            'arduinoId' => (string) (($spot['sensor']['arduinoId'] ?? '') ?: ''),
                            'channel' => (string) (($spot['sensor']['channel'] ?? '') ?: ''),
                            'topic' => (string) (($spot['sensor']['topic'] ?? '') ?: ''),
                        ],
                        'updatedAt' => (string) ($spot['updatedAt'] ?? now()->toIso8601String()),
                    ];
                })->values()->all(),
            ],
            'created_by_admin_id' => $existing ? (string) ($existing->created_by_admin_id ?? $adminId) : $adminId,
            'updated_by_admin_id' => $adminId,
        ];
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
}
