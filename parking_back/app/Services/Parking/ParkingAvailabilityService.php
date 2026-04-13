<?php

namespace App\Services\Parking;

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
        $this->ensureDefaults();

        return ParkingAvailability::query()
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
            $record->is_arduino = true;
            $record->total_spots = $resolvedTotal;
            $record->available_spots = $resolvedAvailable;
            $record->last_sensor_at = CarbonImmutable::now();
            $record->save();
        }

        return $this->toPayload($record->fresh() ?? $record);
    }

    public function ensureDefaults(): void
    {
        foreach (self::DEFAULT_PARKINGS as $parking) {
            $existing = ParkingAvailability::query()
                ->where('parking_name', $parking['name'])
                ->first();

            if ($existing) {
                continue;
            }

            ParkingAvailability::query()->create([
                'parking_id' => $parking['id'],
                'parking_name' => $parking['name'],
                'total_spots' => (int) $parking['total'],
                'available_spots' => (int) $parking['total'],
                'is_arduino' => (bool) $parking['arduino'],
                'last_sensor_at' => null,
            ]);
        }
    }

    private function findOrCreate(
        string $parkingName,
        ?string $parkingId = null,
        bool $forceArduino = false,
    ): ?ParkingAvailability
    {
        $name = trim($parkingName);
        $id = trim((string) ($parkingId ?? ''));
        if ($name === '') {
            return null;
        }

        $this->ensureDefaults();

        if ($id !== '') {
            $byId = ParkingAvailability::query()
                ->where('parking_id', $id)
                ->first();

            if ($byId) {
                if ($name !== '' && (string) ($byId->parking_name ?? '') !== $name) {
                    $byId->parking_name = $name;
                    $byId->save();
                }

                return $byId;
            }
        }

        $record = ParkingAvailability::query()
            ->where('parking_name', $name)
            ->first();

        if ($record) {
            return $record;
        }

        if ($forceArduino || $name === self::ARDUINO_PARKING_NAME) {
            return ParkingAvailability::query()->create([
                'parking_id' => 'arduino-sim',
                'parking_name' => self::ARDUINO_PARKING_NAME,
                'total_spots' => 6,
                'available_spots' => 6,
                'is_arduino' => true,
                'last_sensor_at' => null,
            ]);
        }

        return ParkingAvailability::query()->create([
            'parking_id' => $id === '' ? null : $id,
            'parking_name' => $name,
            'total_spots' => self::DEFAULT_TOTAL_SPOTS,
            'available_spots' => self::DEFAULT_TOTAL_SPOTS,
            'is_arduino' => false,
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
