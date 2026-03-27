<?php

namespace Database\Seeders;

use App\Models\Admin;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class AdminSeeder extends Seeder
{
    public function run(): void
    {
        Admin::query()->updateOrCreate(
            ['email' => env('ADMIN_EMAIL', 'admin@parking.local')],
            [
                'name' => env('ADMIN_NAME', 'Platform Admin'),
                'phone' => env('ADMIN_PHONE', '+10000000000'),
                'password' => Hash::make((string) env('ADMIN_PASSWORD', 'ChangeMe123!')),
            ]
        );
    }
}
