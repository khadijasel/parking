<?php

namespace Database\Seeders;

use App\Models\Admin;
use App\Models\Parking;
use Illuminate\Database\Seeder;

class ArduinoParkingSeeder extends Seeder
{
    public function run(): void
    {
        $admin = Admin::query()
            ->where('email', env('ADMIN_EMAIL', 'admin@parking.local'))
            ->first();

        if (! $admin) {
            $admin = Admin::query()->first();
        }

        $adminId = $admin ? (string) $admin->getKey() : '';

        Parking::query()->updateOrCreate(
            ['parking_id' => 'arduino-sim'],
            [
                'name' => 'Notre parking',
                'address' => 'Zone test IoT',
                'owner_account' => [
                    'name' => 'Owner Notre Parking',
                    'email' => 'owner.notre@parking.local',
                    'phone' => '+213000000000',
                ],
                'location' => [
                    'lat' => 34.8859,
                    'lng' => -1.3161,
                ],
                'capacity' => 6,
                'walking_time' => '2 mins de marche',
                'rating' => 4.7,
                'price_per_hour' => 80,
                'available_spots' => 6,
                'last_update' => 'Simulation Arduino',
                'is_open_24h' => true,
                'equipments' => [
                    'Capteurs IoT',
                    'Videosurveillance',
                    'Securite 24/7',
                ],
                'tags' => ['Arduino', 'Simulation'],
                'image_url' => 'https://images.unsplash.com/photo-1486006920555-c77dcf18193c?auto=format&fit=crop&w=1200&q=80',
                'max_vehicle_height_meters' => 2.0,
                'supported_vehicle_types' => ['car', 'moto'],
                'near_telepherique' => false,
                'indoor_map' => [
                    'floor' => 'B1',
                    'zone' => 'Zone A',
                    'grid' => [
                        'rows' => 3,
                        'cols' => 4,
                        'laneRows' => [1],
                    ],
                    'spots' => [
                        // Rangée haute (row 0) : A1, P3, P5
                        [
                            'spotId' => 'A1',
                            'label' => 'A1',
                            'row' => 0,
                            'col' => 0,
                            'type' => 'STANDARD',
                            'state' => 'AVAILABLE',
                            'sensor' => [
                                'arduinoId' => 'arduino-sim',
                                'channel' => '',
                                'topic' => '',
                            ],
                            'updatedAt' => now()->toIso8601String(),
                        ],
                        [
                            'spotId' => 'P3',
                            'label' => 'P3',
                            'row' => 0,
                            'col' => 1,
                            'type' => 'STANDARD',
                            'state' => 'AVAILABLE',
                            'sensor' => [
                                'arduinoId' => 'arduino-sim',
                                'channel' => '',
                                'topic' => '',
                            ],
                            'updatedAt' => now()->toIso8601String(),
                        ],
                        [
                            'spotId' => 'P5',
                            'label' => 'P5',
                            'row' => 0,
                            'col' => 2,
                            'type' => 'STANDARD',
                            'state' => 'AVAILABLE',
                            'sensor' => [
                                'arduinoId' => 'arduino-sim',
                                'channel' => '',
                                'topic' => '',
                            ],
                            'updatedAt' => now()->toIso8601String(),
                        ],
                        // Rangée basse (row 2) : P2, P4, P6
                        [
                            'spotId' => 'P2',
                            'label' => 'P2',
                            'row' => 2,
                            'col' => 0,
                            'type' => 'STANDARD',
                            'state' => 'AVAILABLE',
                            'sensor' => [
                                'arduinoId' => 'arduino-sim',
                                'channel' => '',
                                'topic' => '',
                            ],
                            'updatedAt' => now()->toIso8601String(),
                        ],
                        [
                            'spotId' => 'P4',
                            'label' => 'P4',
                            'row' => 2,
                            'col' => 1,
                            'type' => 'STANDARD',
                            'state' => 'AVAILABLE',
                            'sensor' => [
                                'arduinoId' => 'arduino-sim',
                                'channel' => '',
                                'topic' => '',
                            ],
                            'updatedAt' => now()->toIso8601String(),
                        ],
                        [
                            'spotId' => 'P6',
                            'label' => 'P6',
                            'row' => 2,
                            'col' => 2,
                            'type' => 'STANDARD',
                            'state' => 'AVAILABLE',
                            'sensor' => [
                                'arduinoId' => 'arduino-sim',
                                'channel' => '',
                                'topic' => '',
                            ],
                            'updatedAt' => now()->toIso8601String(),
                        ],
                    ],
                ],
                'created_by_admin_id' => $adminId,
                'updated_by_admin_id' => $adminId,
            ]
        );
    }
}
