<?php

use App\Http\Controllers\Api\Auth\AdminAuthController;
use App\Http\Controllers\Api\Auth\OwnerAuthController;
use App\Http\Controllers\Api\Auth\UserAuthController;
use Illuminate\Support\Facades\Route;

Route::prefix('user/auth')->group(function (): void {
	Route::post('register', [UserAuthController::class, 'register']);
	Route::post('login', [UserAuthController::class, 'login']);

	Route::middleware('auth:user')->group(function (): void {
		Route::post('logout', [UserAuthController::class, 'logout']);
		Route::get('me', [UserAuthController::class, 'me']);
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