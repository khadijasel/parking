<?php

use App\Models\Reservation;
use App\Services\Parking\ParkingAvailabilityService;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Artisan::command('reservations:purge-cancelled', function () {
    $threshold = CarbonImmutable::now()->subDay();

    $deleted = Reservation::query()
        ->whereIn('reservation_status', [
            'cancelled_by_user',
            'cancelled_timeout',
            'cancelled',
            'expired',
        ])
        ->where(function ($query) use ($threshold): void {
            $query->where('cancelled_at', '<=', $threshold)
                ->orWhere(function ($fallback) use ($threshold): void {
                    $fallback->whereNull('cancelled_at')
                        ->where('updated_at', '<=', $threshold);
                });
        })
        ->delete();

    $this->info("Purge complete. Deleted {$deleted} cancelled reservations.");
})->purpose('Delete cancelled reservations older than 24 hours');

Schedule::command('reservations:purge-cancelled')->hourly();

Artisan::command('reservations:release-expired', function (ParkingAvailabilityService $availability): void {
    $released = $availability->releaseExpiredReservations();

    $this->info("Released {$released} expired reservation(s).");
})->purpose('Cancel expired active reservations and free their parking spot');

Schedule::command('reservations:release-expired')->everyMinute();
