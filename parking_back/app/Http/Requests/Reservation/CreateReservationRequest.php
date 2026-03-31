<?php

namespace App\Http\Requests\Reservation;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class CreateReservationRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'parking_name' => ['required', 'string', 'max:120'],
            'parking_address' => ['nullable', 'string', 'max:255'],
            'equipments' => ['nullable', 'array'],
            'equipments.*' => ['string', 'max:40'],
            'duration_type' => ['required', Rule::in(['courte', 'journee', 'semaine', 'mois'])],
            'duration_minutes' => ['nullable', 'integer', 'min:0'],
            'amount' => ['nullable', 'numeric', 'min:0'],
            'deposit_amount' => ['nullable', 'numeric', 'min:0'],
        ];
    }
}
