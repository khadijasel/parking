<?php

use App\Http\Controllers\Api\Auth\AdminAuthController;
use App\Http\Controllers\Api\Auth\OwnerAuthController;
use App\Http\Controllers\Api\Auth\UserAuthController;
use App\Http\Controllers\Api\Admin\ParkingController;
use App\Http\Controllers\Api\Admin\UserManagementController;
use App\Http\Controllers\Api\Owner\OwnerParkingSettingsController;
use App\Http\Controllers\Api\ParkingAvailabilityController;
use App\Http\Controllers\Api\PaymentController;
use App\Http\Controllers\Api\ReservationController;
use Illuminate\Support\Facades\Route;

Route::get('parkings/availability', [ParkingAvailabilityController::class, 'index']);
Route::post('parkings/arduino/availability', [ParkingAvailabilityController::class, 'updateArduino']);

Route::prefix('user/auth')->group(function (): void {
	Route::post('register', [UserAuthController::class, 'register']);
	Route::post('login', [UserAuthController::class, 'login']);
	Route::post('google', [UserAuthController::class, 'google']);

	Route::middleware('auth:user')->group(function (): void {
		Route::post('logout', [UserAuthController::class, 'logout']);
		Route::get('me', [UserAuthController::class, 'me']);
		Route::post('profile', [UserAuthController::class, 'updateProfile']);
	});
});

Route::prefix('owner/auth')->group(function (): void {
	Route::post('login', [OwnerAuthController::class, 'login']);

	Route::middleware(['auth:owner', 'owner'])->group(function (): void {
		Route::post('logout', [OwnerAuthController::class, 'logout']);
		Route::get('me', [OwnerAuthController::class, 'me']);
	});
});

Route::prefix('admin/auth')->group(function (): void {
	Route::post('login', [AdminAuthController::class, 'login']);

	Route::middleware(['auth:admin', 'admin'])->group(function (): void {
		Route::post('logout', [AdminAuthController::class, 'logout']);
		Route::get('me', [AdminAuthController::class, 'me']);
		Route::post('owners', [AdminAuthController::class, 'createOwner']);
	});
});

Route::prefix('admin')->middleware(['auth:admin', 'admin'])->group(function (): void {
	Route::get('parkings', [ParkingController::class, 'index']);
	Route::get('parkings/{parkingId}', [ParkingController::class, 'show']);
	Route::post('parkings/layout', [ParkingController::class, 'upsertLayout']);
	Route::delete('parkings/{parkingId}', [ParkingController::class, 'destroy']);
	Route::get('users', [UserManagementController::class, 'index']);
	Route::patch('owners/{ownerId}/status', [UserManagementController::class, 'updateOwnerStatus']);
	Route::get('history', [UserManagementController::class, 'history']);
});

Route::prefix('owner')->middleware(['auth:owner', 'owner'])->group(function (): void {
	Route::get('parkings', [OwnerParkingSettingsController::class, 'index']);
	Route::patch('parkings/{parkingId}/business-settings', [OwnerParkingSettingsController::class, 'updateBusinessSettings']);
});

Route::prefix('user')->middleware('auth:user')->group(function (): void {
	Route::post('reservations', [ReservationController::class, 'store']);
	Route::get('reservations', [ReservationController::class, 'index']);
	Route::get('reservations/{reservationId}', [ReservationController::class, 'show']);
	Route::post('reservations/{reservationId}/go', [ReservationController::class, 'go']);
	Route::post('reservations/{reservationId}/scan-ticket', [ReservationController::class, 'scanTicket']);
	Route::delete('reservations/{reservationId}', [ReservationController::class, 'cancel']);
	Route::get('parking-sessions/current', [ReservationController::class, 'currentSession']);
	Route::post('parking-sessions/exit', [ReservationController::class, 'exitSession']);
	Route::get('parking-sessions/history', [ReservationController::class, 'sessionHistory']);

	Route::post('payments/initiate', [PaymentController::class, 'initiate']);
	Route::post('payments/confirm', [PaymentController::class, 'confirm']);
	Route::get('payments/history', [PaymentController::class, 'history']);
});