<?php

namespace App\Http\Requests\Parking;

use Illuminate\Foundation\Http\FormRequest;

class InfraredSensorReadingsRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'parking_id' => ['required', 'string', 'max:80'],
            'device_id' => ['nullable', 'string', 'max:120'],
            'sent_at' => ['nullable', 'date'],
            'readings' => ['required', 'array', 'min:1', 'max:500'],
            'readings.*.spot_id' => ['nullable', 'string', 'max:80'],
            'readings.*.spot_label' => ['nullable', 'string', 'max:80'],
            'readings.*.channel' => ['nullable', 'string', 'max:120'],
            'readings.*.topic' => ['nullable', 'string', 'max:255'],
            'readings.*.arduino_id' => ['nullable', 'string', 'max:120'],
            'readings.*.occupied' => ['required', 'boolean'],
            'readings.*.detected_at' => ['nullable', 'date'],
        ];
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator): void {
            $readings = $this->input('readings', []);
            if (! is_array($readings)) {
                return;
            }

            foreach ($readings as $index => $reading) {
                $row = is_array($reading) ? $reading : [];
                $hasIdentifier = $this->hasNonEmpty($row['spot_id'] ?? null)
                    || $this->hasNonEmpty($row['spot_label'] ?? null)
                    || $this->hasNonEmpty($row['channel'] ?? null)
                    || $this->hasNonEmpty($row['topic'] ?? null);

                if (! $hasIdentifier) {
                    $validator->errors()->add(
                        "readings.$index",
                        'Each reading must include spot_id, spot_label, channel, or topic.',
                    );
                }
            }
        });
    }

    private function hasNonEmpty(mixed $value): bool
    {
        return trim((string) $value) !== '';
    }
}
