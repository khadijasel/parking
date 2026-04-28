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

export const listAdminUsers = async ({ authHeaders }) => {
  try {
    const response = await fetch('/api/admin/users', {
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
      data: Array.isArray(payload?.data?.users) ? payload.data.users : [],
      totals: payload?.data?.totals ?? null,
    }
  } catch (error) {
    return {
      ok: false,
      message: `Chargement utilisateurs echoue: ${String(error?.message ?? error)}`,
    }
  }
}

export const updateAdminOwnerStatus = async ({ ownerId, payload, authHeaders }) => {
  const safeOwnerId = encodeURIComponent(String(ownerId ?? '').trim())

  if (!safeOwnerId) {
    return {
      ok: false,
      message: 'Owner ID invalide.',
    }
  }

  try {
    const response = await fetch(`/api/admin/owners/${safeOwnerId}/status`, {
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
      data: body?.data?.owner ?? null,
    }
  } catch (error) {
    return {
      ok: false,
      message: `Mise a jour owner echouee: ${String(error?.message ?? error)}`,
    }
  }
}

export const listAdminGlobalHistory = async ({ authHeaders, limit = 120 } = {}) => {
  const safeLimit = Math.max(20, Math.min(Number(limit) || 120, 300))

  try {
    const response = await fetch(`/api/admin/history?limit=${encodeURIComponent(safeLimit)}`, {
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
      data: Array.isArray(payload?.data?.events) ? payload.data.events : [],
    }
  } catch (error) {
    return {
      ok: false,
      message: `Chargement historique echoue: ${String(error?.message ?? error)}`,
    }
  }
}
