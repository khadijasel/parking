<?php

namespace App\Services\Owner;

use App\Models\Parking;
use App\Models\ParkingOwner;
use Illuminate\Support\Collection;

class OwnerParkingSettingsService
{
    public function upsertLayoutForOwner(ParkingOwner $owner, array $payload): array
    {
        $existing = $this->findAnyForOwner($owner);
        $attributes = $this->toPersistenceAttributes($payload, $owner, $existing);

        if ($existing) {
            $existing->fill($attributes);
            $existing->save();

            return [
                'parking' => $existing->fresh() ?? $existing,
                'created' => false,
            ];
        }

        /** @var Parking $parking */
        $parking = Parking::query()->create([
            'parking_id' => (string) ($payload['parkingId'] ?? ''),
            ...$attributes,
        ]);

        return [
            'parking' => $parking,
            'created' => true,
        ];
    }

    public function listForOwner(ParkingOwner $owner): Collection
    {
        $email = $this->normalizeEmail($owner->email ?? '');

        return Parking::query()
            ->orderByDesc('updated_at')
            ->get()
            ->filter(fn (Parking $parking): bool => $this->extractOwnerEmail($parking) === $email)
            ->values();
    }

    public function findForOwner(ParkingOwner $owner, string $parkingId): ?Parking
    {
        $email = $this->normalizeEmail($owner->email ?? '');

        /** @var Parking|null $parking */
        $parking = Parking::query()
            ->where('parking_id', $parkingId)
            ->first();

        if (! $parking) {
            return null;
        }

        if ($this->extractOwnerEmail($parking) !== $email) {
            return null;
        }

        return $parking;
    }

    public function updateBusinessSettings(Parking $parking, ParkingOwner $owner, array $payload): Parking
    {
        $workingDays = collect($payload['workingDays'] ?? [])
            ->map(fn (string $day): string => strtoupper(trim($day)))
            ->unique()
            ->values()
            ->all();

        $pricing = [
            'currency' => 'DZD',
            'hourlyRateDzd' => (float) ($payload['pricing']['hourlyRateDzd'] ?? 0),
            'dailyRateDzd' => (float) ($payload['pricing']['dailyRateDzd'] ?? 0),
            'monthlyRateDzd' => isset($payload['pricing']['monthlyRateDzd'])
                ? (float) $payload['pricing']['monthlyRateDzd']
                : null,
        ];

        $businessSettings = [
            'workingDays' => $workingDays,
            'openingTime' => (string) ($payload['openingTime'] ?? '08:00'),
            'closingTime' => (string) ($payload['closingTime'] ?? '20:00'),
            'pricing' => $pricing,
        ];

        $parking->fill([
            'working_days' => $workingDays,
            'opening_time' => $businessSettings['openingTime'],
            'closing_time' => $businessSettings['closingTime'],
            'pricing' => $pricing,
            'business_settings' => $businessSettings,
            'updated_by_owner_id' => (string) $owner->getAuthIdentifier(),
        ]);

        $parking->save();

        /** @var Parking $fresh */
        $fresh = $parking->fresh() ?? $parking;

        return $fresh;
    }

    private function findAnyForOwner(ParkingOwner $owner): ?Parking
    {
        $email = $this->normalizeEmail($owner->email ?? '');

        /** @var Parking|null $parking */
        $parking = Parking::query()
            ->orderByDesc('updated_at')
            ->get()
            ->first(fn (Parking $item): bool => $this->extractOwnerEmail($item) === $email);

        return $parking;
    }

    private function toPersistenceAttributes(array $payload, ParkingOwner $owner, ?Parking $existing = null): array
    {
        $existingIndoorMap = (array) ($existing?->indoor_map ?? []);
        $existingSpots = (array) ($existingIndoorMap['spots'] ?? []);
        $indoorMapPayload = (array) ($payload['indoorMap'] ?? []);
        $gridPayload = (array) ($indoorMapPayload['grid'] ?? []);
        $spotsPayload = $this->normalizeSpots(
            $indoorMapPayload['spots'] ?? [],
            $gridPayload,
            $existingSpots
        );

        $workingDays = collect((array) ($existing?->working_days ?? []))
            ->map(fn (string $day): string => strtoupper(trim($day)))
            ->unique()
            ->values()
            ->all();

        $pricing = [
            'currency' => 'DZD',
            'hourlyRateDzd' => isset($payload['pricePerHour']) ? (float) $payload['pricePerHour'] : (float) ($existing?->pricing['hourlyRateDzd'] ?? 0),
            'dailyRateDzd' => (float) ($existing?->pricing['dailyRateDzd'] ?? 0),
            'monthlyRateDzd' => isset($existing?->pricing['monthlyRateDzd'])
                ? (float) $existing?->pricing['monthlyRateDzd']
                : null,
        ];

        $businessSettings = [
            'workingDays' => $workingDays,
            'openingTime' => (string) ($existing?->opening_time ?? '08:00'),
            'closingTime' => (string) ($existing?->closing_time ?? '20:00'),
            'pricing' => $pricing,
        ];

        return [
            'name' => (string) $payload['name'],
            'address' => (string) $payload['address'],
            'owner_account' => [
                'name' => (string) ($owner->name ?? ''),
                'email' => strtolower((string) ($owner->email ?? '')),
                'phone' => (string) ($owner->phone ?? ''),
            ],
            'location' => [
                'lat' => (float) ($payload['location']['lat'] ?? 0),
                'lng' => (float) ($payload['location']['lng'] ?? 0),
            ],
            'capacity' => (int) ($payload['capacity'] ?? 0),
            'walking_time' => (string) ($payload['walkingTime'] ?? $existing?->walking_time ?? ''),
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
            'equipments' => $this->normalizeStringArray($payload['equipments'] ?? $existing?->equipments ?? []),
            'tags' => $this->normalizeStringArray($payload['tags'] ?? $existing?->tags ?? []),
            'image_url' => (string) ($payload['imageUrl'] ?? $existing?->image_url ?? ''),
            'max_vehicle_height_meters' => array_key_exists('maxVehicleHeightMeters', $payload)
                ? ($payload['maxVehicleHeightMeters'] === null ? null : (float) $payload['maxVehicleHeightMeters'])
                : $existing?->max_vehicle_height_meters,
            'supported_vehicle_types' => $this->normalizeStringArray($payload['supportedVehicleTypes'] ?? $existing?->supported_vehicle_types ?? []),
            'near_telepherique' => array_key_exists('nearTelepherique', $payload)
                ? (bool) ($payload['nearTelepherique'] ?? false)
                : (bool) ($existing?->near_telepherique ?? false),
            'indoor_map' => [
                'floor' => (string) ($indoorMapPayload['floor'] ?? $existingIndoorMap['floor'] ?? 'B1'),
                'zone' => (string) ($indoorMapPayload['zone'] ?? $existingIndoorMap['zone'] ?? 'Zone A'),
                'grid' => [
                    'rows' => (int) ($gridPayload['rows'] ?? $existingIndoorMap['grid']['rows'] ?? 1),
                    'cols' => (int) ($gridPayload['cols'] ?? $existingIndoorMap['grid']['cols'] ?? 1),
                    'laneRows' => collect($gridPayload['laneRows'] ?? $existingIndoorMap['grid']['laneRows'] ?? [])->map(fn ($row): int => (int) $row)->values()->all(),
                    'laneCols' => collect($gridPayload['laneCols'] ?? $existingIndoorMap['grid']['laneCols'] ?? [])->map(fn ($col): int => (int) $col)->values()->all(),
                ],
                'spots' => $spotsPayload,
            ],
            'working_days' => $workingDays,
            'opening_time' => (string) ($existing?->opening_time ?? '08:00'),
            'closing_time' => (string) ($existing?->closing_time ?? '20:00'),
            'pricing' => $pricing,
            'business_settings' => $businessSettings,
            'updated_by_owner_id' => (string) $owner->getAuthIdentifier(),
        ];
    }

    private function normalizeSpots(mixed $spots, array $gridPayload, array $existingSpots = []): array
    {
        if (is_array($spots) && count($spots)) {
            return collect($spots)->map(function ($spot): array {
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
            })->values()->all();
        }

        if (count($existingSpots)) {
            return $existingSpots;
        }

        return $this->generateSpotsFromGrid($gridPayload);
    }

    private function generateSpotsFromGrid(array $gridPayload): array
    {
        $rows = max(1, (int) ($gridPayload['rows'] ?? 1));
        $cols = max(1, (int) ($gridPayload['cols'] ?? 1));
        $laneRows = collect($gridPayload['laneRows'] ?? [])->map(fn ($row): int => (int) $row)->all();
        $laneCols = collect($gridPayload['laneCols'] ?? [])->map(fn ($col): int => (int) $col)->all();
        $now = now()->toIso8601String();

        $spots = [];
        for ($row = 0; $row < $rows; $row++) {
            if (in_array($row, $laneRows, true)) {
                continue;
            }

            for ($col = 0; $col < $cols; $col++) {
                if (in_array($col, $laneCols, true)) {
                    continue;
                }

                $spots[] = [
                    'spotId' => sprintf('R%sC%s', $row + 1, $col + 1),
                    'label' => sprintf('P%s', count($spots) + 1),
                    'row' => $row,
                    'col' => $col,
                    'type' => 'STANDARD',
                    'state' => 'AVAILABLE',
                    'sensor' => [
                        'arduinoId' => '',
                        'channel' => '',
                        'topic' => '',
                    ],
                    'updatedAt' => $now,
                ];
            }
        }

        return $spots;
    }

    public function toOwnerPayload(Parking $parking): array
    {
        $location = (array) ($parking->location ?? []);
        $ownerAccount = (array) ($parking->owner_account ?? []);
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
                    'updatedAt' => (string) ($spotArray['updatedAt'] ?? ''),
                ];
            })
            ->values()
            ->all();

        $availableSpots = $this->resolveAvailableSpots($parking, $spots);

        $businessSettings = $this->resolveBusinessSettings($parking);

        return [
            'parkingId' => (string) ($parking->parking_id ?? $parking->getKey()),
            'name' => (string) ($parking->name ?? ''),
            'address' => (string) ($parking->address ?? ''),
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
            'ownerAccount' => [
                'name' => (string) ($ownerAccount['name'] ?? ''),
                'email' => (string) ($ownerAccount['email'] ?? ''),
                'phone' => (string) ($ownerAccount['phone'] ?? ''),
            ],
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
            'businessSettings' => $businessSettings,
            'updatedAt' => $parking->updated_at?->toIso8601String(),
            'createdAt' => $parking->created_at?->toIso8601String(),
        ];
    }

    private function resolveBusinessSettings(Parking $parking): array
    {
        $settings = (array) ($parking->business_settings ?? []);
        $legacyWorkingDays = collect($parking->working_days ?? [])->map(fn ($day): string => strtoupper((string) $day))->values()->all();
        $legacyPricing = (array) ($parking->pricing ?? []);

        $workingDays = collect($settings['workingDays'] ?? $legacyWorkingDays)
            ->filter(fn ($day): bool => is_string($day) && $day !== '')
            ->map(fn ($day): string => strtoupper(trim($day)))
            ->unique()
            ->values()
            ->all();

        if (!count($workingDays)) {
            $workingDays = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY'];
        }

        $pricing = (array) ($settings['pricing'] ?? $legacyPricing);

        return [
            'workingDays' => $workingDays,
            'openingTime' => (string) ($settings['openingTime'] ?? $parking->opening_time ?? '08:00'),
            'closingTime' => (string) ($settings['closingTime'] ?? $parking->closing_time ?? '20:00'),
            'pricing' => [
                'currency' => 'DZD',
                'hourlyRateDzd' => (float) ($pricing['hourlyRateDzd'] ?? 0),
                'dailyRateDzd' => (float) ($pricing['dailyRateDzd'] ?? 0),
                'monthlyRateDzd' => isset($pricing['monthlyRateDzd'])
                    ? (float) $pricing['monthlyRateDzd']
                    : null,
            ],
        ];
    }

    private function extractOwnerEmail(Parking $parking): string
    {
        $ownerAccount = $this->normalizeArray($parking->owner_account ?? []);

        return $this->normalizeEmail($ownerAccount['email'] ?? '');
    }

    /**
     * @return array<string, mixed>
     */
    private function normalizeArray(mixed $value): array
    {
        if (is_array($value)) {
            return $value;
        }

        if (is_string($value)) {
            $decoded = json_decode($value, true);
            return is_array($decoded) ? $decoded : [];
        }

        if ($value instanceof \JsonSerializable) {
            $serialized = $value->jsonSerialize();
            return is_array($serialized) ? $serialized : [];
        }

        if (is_object($value)) {
            return (array) $value;
        }

        return [];
    }

    private function normalizeEmail(mixed $value): string
    {
        return strtolower(trim((string) $value));
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
