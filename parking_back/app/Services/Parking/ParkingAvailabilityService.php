<?php

namespace App\Services\Parking;

use App\Models\Parking;
use App\Models\ParkingAvailability;
use Carbon\CarbonImmutable;

class ParkingAvailabilityService
{
    private const DEFAULT_TOTAL_SPOTS = 20;

    private const ARDUINO_PARKING_NAME = 'Notre parking';

    private const DEFAULT_PARKINGS = [
        ['id' => '1', 'name' => 'Parking Didouche Mourad', 'total' => 20, 'arduino' => false],
        ['id' => '2', 'name' => 'Parking Port d\'Alger', 'total' => 35, 'arduino' => false],
        ['id' => '3', 'name' => 'Parking Grande Poste', 'total' => 10, 'arduino' => false],
        ['id' => '4', 'name' => 'Parking Place des Martyrs', 'total' => 15, 'arduino' => false],
        ['id' => '5', 'name' => 'Parking Audin', 'total' => 8, 'arduino' => false],
        ['id' => '6', 'name' => 'Parking Centre Ville Tlemcen', 'total' => 24, 'arduino' => false],
        ['id' => '7', 'name' => 'Parking Lalla Setti', 'total' => 18, 'arduino' => false],
        ['id' => '8', 'name' => 'Parking Imama Tlemcen', 'total' => 32, 'arduino' => false],
        ['id' => '9', 'name' => 'Parking Kiffane', 'total' => 21, 'arduino' => false],
        ['id' => '10', 'name' => 'Parking Universite Tlemcen', 'total' => 45, 'arduino' => false],
        ['id' => 'arduino-sim', 'name' => self::ARDUINO_PARKING_NAME, 'total' => 6, 'arduino' => true],
    ];

    public function list(): array
    {
        $seed = $this->ensureDefaults();

        $ids = collect($seed)
            ->map(fn (array $item): string => trim((string) ($item['id'] ?? '')))
            ->filter()
            ->unique()
            ->values()
            ->all();

        $query = ParkingAvailability::query();
        if (count($ids)) {
            $query->whereIn('parking_id', $ids);
        }

        return $query
            ->orderBy('parking_name')
            ->get()
            ->map(fn (ParkingAvailability $item): array => $this->toPayload($item))
            ->values()
            ->all();
    }

    public function lockSpot(string $parkingName, ?string $parkingId = null): bool
    {
        $record = $this->findOrCreate($parkingName, $parkingId);
        if (! $record) {
            return false;
        }

        if ((int) ($record->available_spots ?? 0) <= 0) {
            return false;
        }

        $updated = ParkingAvailability::query()
            ->where('_id', $record->getKey())
            ->where('available_spots', '>', 0)
            ->decrement('available_spots');

        return $updated > 0;
    }

    public function releaseSpot(string $parkingName, ?string $parkingId = null): void
    {
        $record = $this->findOrCreate($parkingName, $parkingId);
        if (! $record) {
            return;
        }

        $total = max(0, (int) ($record->total_spots ?? 0));
        $available = max(0, (int) ($record->available_spots ?? 0));

        if ($available >= $total) {
            return;
        }

        $record->available_spots = min($total, $available + 1);
        $record->save();
    }

    public function updateArduinoAvailability(int $availableSpots, ?int $totalSpots = null): array
    {
        $record = $this->findOrCreate(
            self::ARDUINO_PARKING_NAME,
            'arduino-sim',
            forceArduino: true,
        );

        $resolvedTotal = $totalSpots ?? (int) ($record?->total_spots ?? 6);
        if ($resolvedTotal <= 0) {
            $resolvedTotal = 6;
        }

        $resolvedAvailable = max(0, min($availableSpots, $resolvedTotal));

        if (! $record) {
            $record = ParkingAvailability::query()->create([
                'parking_id' => 'arduino-sim',
                'parking_name' => self::ARDUINO_PARKING_NAME,
                'total_spots' => $resolvedTotal,
                'available_spots' => $resolvedAvailable,
                'is_arduino' => true,
                'last_sensor_at' => CarbonImmutable::now(),
            ]);
        } else {
            $record->parking_id = (string) ($record->parking_id ?: 'arduino-sim');
            $record->parking_name = self::ARDUINO_PARKING_NAME;
            $record->is_arduino = true;
            $record->total_spots = $resolvedTotal;
            $record->available_spots = $resolvedAvailable;
            $record->last_sensor_at = CarbonImmutable::now();
            $record->save();
        }

        return $this->toPayload($record->fresh() ?? $record);
    }

    public function ensureDefaults(): array
    {
        $seed = $this->resolveSeedParkings();

        foreach ($seed as $parking) {
            $id = trim((string) ($parking['id'] ?? ''));
            $name = trim((string) ($parking['name'] ?? ''));

            if ($name === '') {
                continue;
            }

            $total = max(1, (int) ($parking['total'] ?? self::DEFAULT_TOTAL_SPOTS));
            $isArduino = (bool) ($parking['arduino'] ?? false);

            $this->upsertAvailabilityRecord(
                $id,
                $name,
                $total,
                $isArduino,
            );
        }

        return $seed;
    }

    private function findOrCreate(
        string $parkingName,
        ?string $parkingId = null,
        bool $forceArduino = false,
    ): ?ParkingAvailability
    {
        $name = trim($parkingName);
        $id = trim((string) ($parkingId ?? ''));

        if ($name === '' && $id === '') {
            return null;
        }

        $this->ensureDefaults();

        if ($forceArduino) {
            $resolvedId = $id !== '' ? $id : 'arduino-sim';
            $resolvedName = $name !== '' ? $name : self::ARDUINO_PARKING_NAME;

            return $this->upsertAvailabilityRecord(
                $resolvedId,
                $resolvedName,
                6,
                true,
            );
        }

        $parking = $this->resolveParkingRecord($id, $name);
        if (! $parking) {
            return null;
        }

        $resolvedId = $this->resolveParkingId($parking);
        $resolvedName = trim((string) ($parking->name ?? $name));
        $total = max(1, $this->resolveTotalSpotsFromParking($parking));
        $isArduino = $this->isArduinoParking($resolvedId, $resolvedName);

        return $this->upsertAvailabilityRecord(
            $resolvedId,
            $resolvedName,
            $total,
            $isArduino,
        );
    }

    /**
     * @return array<int, array{id: string, name: string, total: int, arduino: bool}>
     */
    private function resolveSeedParkings(): array
    {
        $parkings = Parking::query()->get();

        if ($parkings->isEmpty()) {
            return self::DEFAULT_PARKINGS;
        }

        return $parkings
            ->map(function (Parking $parking): array {
                $id = $this->resolveParkingId($parking);
                $name = trim((string) ($parking->name ?? ''));
                $total = max(1, $this->resolveTotalSpotsFromParking($parking));

                return [
                    'id' => $id,
                    'name' => $name,
                    'total' => $total,
                    'arduino' => $this->isArduinoParking($id, $name),
                ];
            })
            ->filter(fn (array $item): bool => $item['name'] !== '')
            ->values()
            ->all();
    }

    private function resolveParkingRecord(string $parkingId, string $parkingName): ?Parking
    {
        $parking = null;
        $normalizedId = trim($parkingId);
        $normalizedName = trim($parkingName);

        if ($normalizedId !== '') {
            /** @var Parking|null $parking */
            $parking = Parking::query()->where('parking_id', $normalizedId)->first();

            if (! $parking) {
                /** @var Parking|null $parking */
                $parking = Parking::query()->find($normalizedId);
            }
        }

        if (! $parking && $normalizedName !== '') {
            /** @var Parking|null $parking */
            $parking = Parking::query()->where('name', $normalizedName)->first();
        }

        return $parking;
    }

    private function resolveParkingId(Parking $parking): string
    {
        $parkingId = trim((string) ($parking->parking_id ?? ''));

        if ($parkingId !== '') {
            return $parkingId;
        }

        return (string) $parking->getKey();
    }

    private function resolveTotalSpotsFromParking(Parking $parking): int
    {
        $capacity = max(0, (int) ($parking->capacity ?? 0));
        if ($capacity > 0) {
            return $capacity;
        }

        $indoorMap = (array) ($parking->indoor_map ?? []);
        $spots = $indoorMap['spots'] ?? [];
        if (is_array($spots) && count($spots) > 0) {
            return count($spots);
        }

        $available = max(0, (int) ($parking->available_spots ?? 0));
        if ($available > 0) {
            return $available;
        }

        return self::DEFAULT_TOTAL_SPOTS;
    }

    private function isArduinoParking(string $parkingId, string $parkingName): bool
    {
        $normalizedName = strtolower($parkingName);

        if ($parkingId === 'arduino-sim') {
            return true;
        }

        if (str_contains($normalizedName, 'arduino')) {
            return true;
        }

        return str_contains($normalizedName, strtolower(self::ARDUINO_PARKING_NAME));
    }

    private function upsertAvailabilityRecord(
        string $parkingId,
        string $parkingName,
        int $totalSpots,
        bool $isArduino,
        ?int $availableOverride = null,
    ): ParkingAvailability {
        $id = trim($parkingId);
        $name = trim($parkingName);
        $total = max(1, $totalSpots);

        $record = null;

        if ($id !== '') {
            $record = ParkingAvailability::query()
                ->where('parking_id', $id)
                ->first();
        }

        if (! $record && $name !== '') {
            $record = ParkingAvailability::query()
                ->where('parking_name', $name)
                ->first();
        }

        $available = $availableOverride;

        if ($record) {
            $record->parking_id = $id !== '' ? $id : (string) ($record->parking_id ?? '');
            $record->parking_name = $name;
            $record->is_arduino = $isArduino;
            $record->total_spots = $total;

            if ($available === null) {
                $available = $record->available_spots;
            }

            $available = max(0, (int) ($available ?? $total));
            $record->available_spots = min($total, $available);
            $record->save();

            return $record;
        }

        $available = max(0, (int) ($available ?? $total));
        $available = min($total, $available);

        return ParkingAvailability::query()->create([
            'parking_id' => $id === '' ? null : $id,
            'parking_name' => $name,
            'total_spots' => $total,
            'available_spots' => $available,
            'is_arduino' => $isArduino,
            'last_sensor_at' => null,
        ]);
    }

    private function toPayload(ParkingAvailability $item): array
    {
        return [
            'parking_id' => (string) ($item->parking_id ?? ''),
            'parking_name' => (string) ($item->parking_name ?? ''),
            'total_spots' => max(0, (int) ($item->total_spots ?? 0)),
            'available_spots' => max(0, (int) ($item->available_spots ?? 0)),
            'is_arduino' => (bool) ($item->is_arduino ?? false),
            'last_sensor_at' => $item->last_sensor_at?->toIso8601String(),
            'updated_at' => $item->updated_at?->toIso8601String(),
        ];
    }
}
