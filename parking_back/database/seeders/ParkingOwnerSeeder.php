<?php

namespace Database\Seeders;

use App\Models\ParkingOwner;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class ParkingOwnerSeeder extends Seeder
{
    public function run(): void
    {
        ParkingOwner::query()->updateOrCreate(
            ['email' => 'owner.notre@parking.local'],
            [
                'name' => 'Owner Notre Parking',
                'phone' => '+213000000000',
                'password' => Hash::make('OwnerParking123!'),
                'account_status' => 'active',
                'subscription_status' => 'active',
                'subscription_ends_at' => null,
                'blocked_at' => null,
                'blocked_reason' => null,
                'last_login_at' => null,
            ]
        );
    }
}
