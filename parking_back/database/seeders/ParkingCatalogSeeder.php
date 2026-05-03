<?php

namespace Database\Seeders;

use App\Models\Admin;
use App\Models\Parking;
use Illuminate\Database\Seeder;

class ParkingCatalogSeeder extends Seeder
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

        $parkings = [
            [
                'parking_id' => 'algiers-airport',
                'name' => 'Algiers International Airport Houari Boumediene',
                'address' => 'Aeroport d\'Alger, Dar El Beida',
                'capacity' => 2500,
                'walking_time' => '3 mins de marche',
                'rating' => 3.7,
                'price_per_hour' => 150,
                'available_spots' => 2500,
                'last_update' => 'Mise a jour recemment',
                'is_open_24h' => true,
                'equipments' => ['GPL Autorise', 'Bornes electriques', 'Moto', 'Accessible Handi'],
                'tags' => ['Aeroport', 'International'],
                'image_url' => 'https://images.unsplash.com/photo-1503736334956-4c8f8e92946d?auto=format&fit=crop&w=1200&q=80',
                'max_vehicle_height_meters' => 2.4,
                'supported_vehicle_types' => ['car', 'moto'],
                'near_telepherique' => false,
                'location' => ['lat' => 36.6910, 'lng' => 3.2159],
            ],
            [
                'parking_id' => 'port-algiers',
                'name' => 'Port of Algiers',
                'address' => 'Port d\'Alger',
                'capacity' => 500,
                'walking_time' => '6 mins de marche',
                'rating' => 4.0,
                'price_per_hour' => 100,
                'available_spots' => 500,
                'last_update' => 'Mise a jour recemment',
                'is_open_24h' => true,
                'equipments' => ['GPL Autorise', 'Bornes electriques', 'Moto'],
                'tags' => ['Port'],
                'image_url' => 'https://images.unsplash.com/photo-1506521781263-d8422e82f27a?auto=format&fit=crop&w=1200&q=80',
                'max_vehicle_height_meters' => 3.0,
                'supported_vehicle_types' => ['car', 'moto', 'truck'],
                'near_telepherique' => false,
                'location' => ['lat' => 36.7871, 'lng' => 3.0600],
            ],
            [
                'parking_id' => 'bab-ezzouar-mall',
                'name' => 'Bab Ezzouar Mall',
                'address' => 'Bab Ezzouar, Alger',
                'capacity' => 1200,
                'walking_time' => '4 mins de marche',
                'rating' => 4.1,
                'price_per_hour' => 120,
                'available_spots' => 1200,
                'last_update' => 'Mise a jour recemment',
                'is_open_24h' => false,
                'equipments' => ['GPL Autorise', 'Bornes electriques', 'Moto', 'Accessible Handi'],
                'tags' => ['Shopping', 'Proche Tram'],
                'image_url' => 'https://images.unsplash.com/photo-1494526585095-c41746248156?auto=format&fit=crop&w=1200&q=80',
                'max_vehicle_height_meters' => 2.2,
                'supported_vehicle_types' => ['car', 'moto'],
                'near_telepherique' => false,
                'location' => ['lat' => 36.7207, 'lng' => 3.1818],
            ],
            [
                'parking_id' => 'city-center-mall',
                'name' => 'City Center Mall',
                'address' => 'Centre-ville, Alger',
                'capacity' => 800,
                'walking_time' => '4 mins de marche',
                'rating' => 4.0,
                'price_per_hour' => 110,
                'available_spots' => 800,
                'last_update' => 'Mise a jour recemment',
                'is_open_24h' => false,
                'equipments' => ['GPL Autorise', 'Bornes electriques', 'Moto', 'Accessible Handi'],
                'tags' => ['Shopping', 'Proche Tram'],
                'image_url' => 'https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=1200&q=80',
                'max_vehicle_height_meters' => 2.1,
                'supported_vehicle_types' => ['car', 'moto'],
                'near_telepherique' => false,
                'location' => ['lat' => 36.7510, 'lng' => 3.0455],
            ],
            [
                'parking_id' => 'garden-city-mall',
                'name' => 'Garden City Mall',
                'address' => 'Cheraga, Alger',
                'capacity' => 1500,
                'walking_time' => '5 mins de marche',
                'rating' => 4.2,
                'price_per_hour' => 120,
                'available_spots' => 1500,
                'last_update' => 'Mise a jour recemment',
                'is_open_24h' => false,
                'equipments' => ['GPL Autorise', 'Bornes electriques', 'Moto', 'Accessible Handi'],
                'tags' => ['Shopping'],
                'image_url' => 'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?auto=format&fit=crop&w=1200&q=80',
                'max_vehicle_height_meters' => 2.3,
                'supported_vehicle_types' => ['car', 'moto'],
                'near_telepherique' => false,
                'location' => ['lat' => 36.7865, 'lng' => 2.9615],
            ],
            [
                'parking_id' => 'oran-airport',
                'name' => 'Aeroport d\'Oran Ahmed Ben Bella',
                'address' => 'Aeroport d\'Oran, Es Senia',
                'capacity' => 1200,
                'walking_time' => '3 mins de marche',
                'rating' => 4.0,
                'price_per_hour' => 100,
                'available_spots' => 1200,
                'last_update' => 'Mise a jour recemment',
                'is_open_24h' => true,
                'equipments' => ['GPL Autorise', 'Bornes electriques', 'Moto', 'Accessible Handi'],
                'tags' => ['Aeroport', 'International'],
                'image_url' => 'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80',
                'max_vehicle_height_meters' => 2.4,
                'supported_vehicle_types' => ['car', 'moto'],
                'near_telepherique' => false,
                'location' => ['lat' => 35.6239, 'lng' => -0.6212],
            ],
            [
                'parking_id' => 'arduino-sim',
                'name' => 'Notre parking',
                'address' => 'Zone test IoT',
                'capacity' => 6,
                'walking_time' => '2 mins de marche',
                'rating' => 4.7,
                'price_per_hour' => 80,
                'available_spots' => 6,
                'last_update' => 'Simulation Arduino',
                'is_open_24h' => true,
                'equipments' => ['Capteurs IoT', 'Videosurveillance', 'Securite 24/7'],
                'tags' => ['Arduino', 'Simulation'],
                'image_url' => 'https://images.unsplash.com/photo-1486006920555-c77dcf18193c?auto=format&fit=crop&w=1200&q=80',
                'max_vehicle_height_meters' => 2.0,
                'supported_vehicle_types' => ['car', 'moto'],
                'near_telepherique' => false,
                'location' => ['lat' => 34.8859, 'lng' => -1.3161],
            ],
        ];

        foreach ($parkings as $parking) {
            $parking['created_by_admin_id'] = $adminId;
            Parking::query()->updateOrCreate(
                ['parking_id' => $parking['parking_id']],
                $parking,
            );
        }
    }
}
