<?php

namespace App\Services\Payment;

use App\Models\Payment;
use Carbon\CarbonImmutable;

class MockBankService
{
    public const MAX_ATTEMPTS = 3;

    public function process(Payment $payment, ?string $pin): array
    {
        if ((string) $payment->method === 'cash') {
            return $this->markSuccess($payment);
        }

        $attempts = (int) ($payment->pin_attempts ?? 0);

        if ($attempts >= self::MAX_ATTEMPTS) {
            return $this->markBlocked($payment);
        }

        if (! is_string($pin) || strlen($pin) !== 4) {
            return $this->markWrongPin($payment, $attempts + 1);
        }

        return match ($pin) {
            '1234' => $this->markSuccess($payment),
            '0000' => $this->markInsufficientFunds($payment, $attempts + 1),
            '9999' => $this->markTimeout($payment, $attempts),
            default => $this->markWrongPin($payment, $attempts + 1),
        };
    }

    private function markSuccess(Payment $payment): array
    {
        $payment->status = 'success';
        $payment->error_code = null;
        $payment->error_message = null;
        $payment->paid_at = CarbonImmutable::now();
        $payment->save();

        return [
            'success' => true,
            'status' => 'success',
            'error_code' => null,
            'error_message' => null,
            'remaining_attempts' => max(0, self::MAX_ATTEMPTS - (int) ($payment->pin_attempts ?? 0)),
        ];
    }

    private function markInsufficientFunds(Payment $payment, int $attempts): array
    {
        $remainingAttempts = max(0, self::MAX_ATTEMPTS - $attempts);

        if ($remainingAttempts <= 0) {
            return $this->markBlocked($payment);
        }

        $payment->pin_attempts = $attempts;
        $payment->remaining_attempts = $remainingAttempts;
        $payment->status = 'failed';
        $payment->error_code = 'INSUFFICIENT_FUNDS';
        $payment->error_message = 'Solde insuffisant. Choisissez une autre methode.';
        $payment->save();

        return [
            'success' => false,
            'status' => 'failed',
            'error_code' => 'INSUFFICIENT_FUNDS',
            'error_message' => (string) $payment->error_message,
            'remaining_attempts' => $remainingAttempts,
        ];
    }

    private function markTimeout(Payment $payment, int $attempts): array
    {
        $remainingAttempts = max(0, self::MAX_ATTEMPTS - $attempts);

        $payment->remaining_attempts = $remainingAttempts;
        $payment->status = 'timeout';
        $payment->error_code = 'NETWORK_TIMEOUT';
        $payment->error_message = 'Connexion perdue. Votre compte n a pas ete debite.';
        $payment->save();

        return [
            'success' => false,
            'status' => 'timeout',
            'error_code' => 'NETWORK_TIMEOUT',
            'error_message' => (string) $payment->error_message,
            'remaining_attempts' => $remainingAttempts,
        ];
    }

    private function markWrongPin(Payment $payment, int $attempts): array
    {
        $remainingAttempts = max(0, self::MAX_ATTEMPTS - $attempts);

        if ($remainingAttempts <= 0) {
            return $this->markBlocked($payment);
        }

        $suffix = $remainingAttempts > 1 ? 's' : '';

        $payment->pin_attempts = $attempts;
        $payment->remaining_attempts = $remainingAttempts;
        $payment->status = 'failed';
        $payment->error_code = 'WRONG_PIN';
        $payment->error_message = "Code incorrect. Il vous reste {$remainingAttempts} tentative{$suffix}.";
        $payment->save();

        return [
            'success' => false,
            'status' => 'failed',
            'error_code' => 'WRONG_PIN',
            'error_message' => (string) $payment->error_message,
            'remaining_attempts' => $remainingAttempts,
        ];
    }

    private function markBlocked(Payment $payment): array
    {
        $payment->pin_attempts = self::MAX_ATTEMPTS;
        $payment->remaining_attempts = 0;
        $payment->status = 'failed';
        $payment->error_code = 'ACCOUNT_BLOCKED';
        $payment->error_message = 'Compte bloque apres 3 tentatives. Contactez votre banque.';
        $payment->save();

        return [
            'success' => false,
            'status' => 'failed',
            'error_code' => 'ACCOUNT_BLOCKED',
            'error_message' => (string) $payment->error_message,
            'remaining_attempts' => 0,
        ];
    }
}
