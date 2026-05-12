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
        ['id' => 'algiers-airport', 'name' => 'Algiers International Airport Houari Boumediene', 'total' => 2500, 'arduino' => false],
        ['id' => 'port-algiers', 'name' => 'Port of Algiers', 'total' => 500, 'arduino' => false],
        ['id' => 'bab-ezzouar-mall', 'name' => 'Bab Ezzouar Mall', 'total' => 1200, 'arduino' => false],
        ['id' => 'city-center-mall', 'name' => 'City Center Mall', 'total' => 800, 'arduino' => false],
        ['id' => 'garden-city-mall', 'name' => 'Garden City Mall', 'total' => 1500, 'arduino' => false],
        ['id' => 'oran-airport', 'name' => 'Aeroport d\'Oran Ahmed Ben Bella', 'total' => 1200, 'arduino' => false],
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

    public function updateInfraredReadings(
        string $parkingId,
        array $readings,
        ?string $deviceId = null,
        ?CarbonImmutable $sentAt = null,
    ): ?array {
        $identifier = trim($parkingId);
        if ($identifier === '') {
            return null;
        }

        $parking = $this->resolveParkingRecord($identifier, $identifier);
        if (! $parking) {
            return null;
        }

        $indoorMap = (array) ($parking->indoor_map ?? []);
        $spots = collect($indoorMap['spots'] ?? [])
            ->map(fn ($spot): array => (array) $spot)
            ->values()
            ->all();

        if (! count($spots)) {
            throw new \RuntimeException('Parking layout has no spots configured.');
        }

        $receivedAt = $sentAt ?? CarbonImmutable::now();
        $processed = $this->applyInfraredReadingsToSpots($spots, $readings, $deviceId, $receivedAt);

        if ((int) $processed['matched'] <= 0) {
            throw new \RuntimeException('No sensor reading matched a configured parking spot.');
        }

        $updatedSpots = $processed['spots'];
        $totalSpots = max(1, count($updatedSpots));
        $availableSpots = $this->countAvailableSpotsFromLayout($updatedSpots);

        $parking->indoor_map = [
            ...$indoorMap,
            'spots' => $updatedSpots,
        ];
        $parking->available_spots = min($totalSpots, max(0, $availableSpots));
        $parking->last_update = sprintf('Infrared sync %s', $receivedAt->toIso8601String());
        $parking->save();

        $availability = $this->syncAvailabilityRecord(
            $parking,
            $totalSpots,
            (int) $parking->available_spots,
            $receivedAt,
        );

        return [
            'parking_id' => $this->resolveParkingId($parking),
            'parking_name' => (string) ($parking->name ?? ''),
            'total_spots' => $totalSpots,
            'available_spots' => (int) $parking->available_spots,
            'matched_readings' => (int) $processed['matched'],
            'unmatched_readings' => $processed['unmatched'],
            'last_sensor_at' => $receivedAt->toIso8601String(),
            'spots' => $updatedSpots,
            'availability' => $availability,
        ];
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

    private function applyInfraredReadingsToSpots(
        array $spots,
        array $readings,
        ?string $defaultDeviceId,
        CarbonImmutable $receivedAt,
    ): array {
        $indexes = $this->buildSpotIndexes($spots);
        $matched = 0;
        $unmatched = [];

        foreach ($readings as $index => $readingItem) {
            $reading = is_array($readingItem) ? $readingItem : [];
            $spotIndex = $this->resolveSpotIndexForReading($reading, $indexes, $defaultDeviceId);

            if ($spotIndex === null || ! array_key_exists($spotIndex, $spots)) {
                $unmatched[] = [
                    'index' => (int) $index,
                    'spot_id' => trim((string) ($reading['spot_id'] ?? $reading['spotId'] ?? '')),
                    'spot_label' => trim((string) ($reading['spot_label'] ?? $reading['spotLabel'] ?? '')),
                    'channel' => trim((string) ($reading['channel'] ?? '')),
                    'topic' => trim((string) ($reading['topic'] ?? '')),
                ];

                continue;
            }

            $spot = (array) ($spots[$spotIndex] ?? []);
            $currentState = strtoupper(trim((string) ($spot['state'] ?? 'AVAILABLE')));
            $spot['state'] = $this->resolveSpotStateFromReading($reading, $currentState);
            $spot['updatedAt'] = $this->resolveSpotTimestamp($reading, $receivedAt);

            $spots[$spotIndex] = $spot;
            $matched++;
        }

        return [
            'spots' => array_values($spots),
            'matched' => $matched,
            'unmatched' => array_values($unmatched),
        ];
    }

    private function buildSpotIndexes(array $spots): array
    {
        $bySpotId = [];
        $byLabel = [];
        $byTopic = [];
        $byDeviceChannel = [];
        $channelCandidates = [];

        foreach ($spots as $index => $spotItem) {
            $spot = is_array($spotItem) ? $spotItem : [];
            $sensor = (array) ($spot['sensor'] ?? []);

            $spotId = $this->normalizeKey($spot['spotId'] ?? '');
            if ($spotId !== '' && ! array_key_exists($spotId, $bySpotId)) {
                $bySpotId[$spotId] = (int) $index;
            }

            $label = $this->normalizeKey($spot['label'] ?? '');
            if ($label !== '' && ! array_key_exists($label, $byLabel)) {
                $byLabel[$label] = (int) $index;
            }

            $topic = $this->normalizeKey($sensor['topic'] ?? '');
            if ($topic !== '' && ! array_key_exists($topic, $byTopic)) {
                $byTopic[$topic] = (int) $index;
            }

            $channel = $this->normalizeKey($sensor['channel'] ?? '');
            if ($channel !== '') {
                $channelCandidates[$channel] ??= [];
                $channelCandidates[$channel][] = (int) $index;
            }

            $arduinoId = $this->normalizeKey($sensor['arduinoId'] ?? '');
            if ($arduinoId !== '' && $channel !== '') {
                $byDeviceChannel[sprintf('%s|%s', $arduinoId, $channel)] = (int) $index;
            }
        }

        $byUniqueChannel = [];
        foreach ($channelCandidates as $channel => $indexes) {
            $uniqueIndexes = array_values(array_unique($indexes));
            if (count($uniqueIndexes) === 1) {
                $byUniqueChannel[$channel] = (int) $uniqueIndexes[0];
            }
        }

        return [
            'spot_id' => $bySpotId,
            'label' => $byLabel,
            'topic' => $byTopic,
            'device_channel' => $byDeviceChannel,
            'channel' => $byUniqueChannel,
        ];
    }

    private function resolveSpotIndexForReading(array $reading, array $indexes, ?string $defaultDeviceId): ?int
    {
        $spotId = $this->normalizeKey($reading['spot_id'] ?? $reading['spotId'] ?? '');
        if ($spotId !== '' && isset($indexes['spot_id'][$spotId])) {
            return (int) $indexes['spot_id'][$spotId];
        }

        $spotLabel = $this->normalizeKey($reading['spot_label'] ?? $reading['spotLabel'] ?? '');
        if ($spotLabel !== '' && isset($indexes['label'][$spotLabel])) {
            return (int) $indexes['label'][$spotLabel];
        }

        $topic = $this->normalizeKey($reading['topic'] ?? '');
        if ($topic !== '' && isset($indexes['topic'][$topic])) {
            return (int) $indexes['topic'][$topic];
        }

        $channel = $this->normalizeKey($reading['channel'] ?? '');
        $readingDevice = $this->normalizeKey(
            $reading['arduino_id'] ?? $reading['arduinoId'] ?? $defaultDeviceId ?? '',
        );

        if ($channel !== '' && $readingDevice !== '') {
            $deviceChannelKey = sprintf('%s|%s', $readingDevice, $channel);
            if (isset($indexes['device_channel'][$deviceChannelKey])) {
                return (int) $indexes['device_channel'][$deviceChannelKey];
            }
        }

        if ($channel !== '' && isset($indexes['channel'][$channel])) {
            return (int) $indexes['channel'][$channel];
        }

        return null;
    }

    private function resolveSpotStateFromReading(array $reading, string $currentState): string
    {
        $explicitState = strtoupper(trim((string) ($reading['state'] ?? '')));
        if (in_array($explicitState, ['AVAILABLE', 'OCCUPIED', 'RESERVED', 'OFFLINE'], true)) {
            return $explicitState;
        }

        $occupied = filter_var(
            $reading['occupied'] ?? null,
            FILTER_VALIDATE_BOOLEAN,
            FILTER_NULL_ON_FAILURE,
        );

        if ($occupied === true) {
            return 'OCCUPIED';
        }

        if ($occupied === false) {
            return $currentState === 'RESERVED' ? 'RESERVED' : 'AVAILABLE';
        }

        return $currentState;
    }

    private function resolveSpotTimestamp(array $reading, CarbonImmutable $fallback): string
    {
        $timestamp = trim((string) ($reading['detected_at'] ?? ''));
        if ($timestamp === '') {
            return $fallback->toIso8601String();
        }

        try {
            return CarbonImmutable::parse($timestamp)->toIso8601String();
        } catch (\Throwable) {
            return $fallback->toIso8601String();
        }
    }

    private function countAvailableSpotsFromLayout(array $spots): int
    {
        return max(0, collect($spots)
            ->filter(function ($spot): bool {
                $spotArray = is_array($spot) ? $spot : [];
                return strtoupper(trim((string) ($spotArray['state'] ?? ''))) === 'AVAILABLE';
            })
            ->count());
    }

    private function normalizeKey(mixed $value): string
    {
        return strtolower(trim((string) $value));
    }

    private function syncAvailabilityRecord(
        Parking $parking,
        int $totalSpots,
        int $availableSpots,
        ?CarbonImmutable $sensorAt = null,
    ): array {
        $parkingId = $this->resolveParkingId($parking);
        $parkingName = trim((string) ($parking->name ?? ''));
        $resolvedTotal = max(1, $totalSpots);
        $resolvedAvailable = min($resolvedTotal, max(0, $availableSpots));

        $record = $this->upsertAvailabilityRecord(
            $parkingId,
            $parkingName,
            $resolvedTotal,
            $this->isArduinoParking($parkingId, $parkingName),
            $resolvedAvailable,
        );

        if ($sensorAt) {
            $record->last_sensor_at = $sensorAt;
            $record->save();
        }

        return $this->toPayload($record->fresh() ?? $record);
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
