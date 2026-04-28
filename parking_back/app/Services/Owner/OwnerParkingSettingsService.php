<?php

namespace App\Services\Owner;

use App\Models\Parking;
use App\Models\ParkingOwner;
use Illuminate\Support\Collection;

class OwnerParkingSettingsService
{
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
