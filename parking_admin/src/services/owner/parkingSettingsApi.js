const parseResponseBody = async (response) => {
  const text = await response.text()

  if (!text) {
    return null
  }

  try {
    return JSON.parse(text)
  } catch {
    return { message: text }
  }
}

const firstErrorMessage = (errors) => {
  if (!errors || typeof errors !== 'object') {
    return ''
  }

  const values = Object.values(errors)

  for (const value of values) {
    if (Array.isArray(value) && value.length) {
      return String(value[0])
    }

    if (typeof value === 'string' && value) {
      return value
    }
  }

  return ''
}

const extractApiErrorMessage = (payload, fallback = 'Operation echouee.') => {
  const message = String(payload?.message ?? '').trim()
  if (message) {
    return message
  }

  const fieldError = firstErrorMessage(payload?.errors)
  if (fieldError) {
    return fieldError
  }

  return fallback
}

export const listOwnerParkings = async ({ authHeaders }) => {
  try {
    const response = await fetch('/api/owner/parkings', {
      method: 'GET',
      headers: authHeaders(),
    })

    const payload = await parseResponseBody(response)

    if (!response.ok) {
      return {
        ok: false,
        message: extractApiErrorMessage(payload, `HTTP ${response.status}`),
      }
    }

    return {
      ok: true,
      data: Array.isArray(payload?.data) ? payload.data : [],
    }
  } catch (error) {
    return {
      ok: false,
      message: `Chargement parkings owner echoue: ${String(error?.message ?? error)}`,
    }
  }
}

export const updateOwnerBusinessSettings = async ({ parkingId, payload, authHeaders }) => {
  const safeParkingId = encodeURIComponent(String(parkingId ?? '').trim())

  if (!safeParkingId) {
    return {
      ok: false,
      message: 'Parking ID invalide.',
    }
  }

  try {
    const response = await fetch(`/api/owner/parkings/${safeParkingId}/business-settings`, {
      method: 'PATCH',
      headers: authHeaders({
        'Content-Type': 'application/json',
      }),
      body: JSON.stringify(payload ?? {}),
    })

    const body = await parseResponseBody(response)

    if (!response.ok) {
      return {
        ok: false,
        message: extractApiErrorMessage(body, `HTTP ${response.status}`),
      }
    }

    return {
      ok: true,
      data: body?.data ?? null,
    }
  } catch (error) {
    return {
      ok: false,
      message: `Mise a jour des parametres echouee: ${String(error?.message ?? error)}`,
    }
  }
}
