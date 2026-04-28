<script setup>
import { reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { homePathForRole, useAuthStore } from '@/stores/auth'

const router = useRouter()
const route = useRoute()
const authStore = useAuthStore()

const form = reactive({
  email: '',
  password: '',
})

const isLoading = ref(false)
const errorMessage = ref('')

const onSubmit = async () => {
  errorMessage.value = ''

  if (isLoading.value) {
    return
  }

  isLoading.value = true

  try {
    const result = await authStore.login({
      role: 'admin',
      email: form.email,
      password: form.password,
    })

    if (!result.ok) {
      errorMessage.value = result.message
      return
    }

    const queryRedirect = typeof route.query.redirect === 'string' ? route.query.redirect : ''
    const redirectPath = queryRedirect || homePathForRole('admin')

    await router.replace(redirectPath)
  } finally {
    isLoading.value = false
  }
}
</script>

<template>
  <section class="grid min-h-screen bg-[radial-gradient(circle_at_12%_18%,rgba(26,115,232,0.18),transparent_34%),radial-gradient(circle_at_85%_8%,rgba(16,185,129,0.18),transparent_30%)] lg:grid-cols-2">
    <div class="flex items-center justify-center px-5 py-10 sm:px-10">
      <article class="w-full max-w-md rounded-3xl bg-surface-container-lowest p-7 shadow-xl dark:bg-slate-900">
        <p class="text-xs font-semibold uppercase tracking-[0.18em] text-outline">Console Admin</p>
        <h1 class="mt-2 font-headline text-3xl font-extrabold text-on-surface">Connexion administrateur</h1>
        <p class="mt-2 text-sm text-on-surface-variant">Accedez au pilotage global de la plateforme de stationnement.</p>

        <form class="mt-6 space-y-4" @submit.prevent="onSubmit">
          <label class="block text-xs font-semibold uppercase tracking-[0.08em] text-outline">
            Email
            <input
              v-model.trim="form.email"
              type="email"
              placeholder="admin@parking.local"
              class="mt-1 w-full rounded-xl bg-surface-container px-3 py-2.5 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
            />
          </label>

          <label class="block text-xs font-semibold uppercase tracking-[0.08em] text-outline">
            Mot de passe
            <input
              v-model="form.password"
              type="password"
              placeholder="Votre mot de passe"
              class="mt-1 w-full rounded-xl bg-surface-container px-3 py-2.5 text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30"
            />
          </label>

          <p v-if="errorMessage" class="rounded-lg bg-red-50 px-3 py-2 text-xs font-semibold text-red-700">
            {{ errorMessage }}
          </p>

          <button type="submit" class="primary-cta w-full" :disabled="isLoading">
            {{ isLoading ? 'Connexion...' : 'Se connecter en admin' }}
          </button>
        </form>

        <p class="mt-5 text-sm text-on-surface-variant">
          Vous etes proprietaire ?
          <RouterLink to="/auth/owner" class="font-semibold text-primary hover:underline">
            Aller a la connexion owner
          </RouterLink>
        </p>
      </article>
    </div>

    <div class="hidden items-center justify-center px-10 py-10 lg:flex">
      <div class="max-w-lg space-y-4 rounded-3xl border border-outline-variant/30 bg-surface-container-lowest/80 p-8 dark:bg-slate-900/80">
        <p class="text-xs font-semibold uppercase tracking-[0.18em] text-primary">Role Admin</p>
        <h2 class="font-headline text-3xl font-extrabold text-on-surface">Gestion globale multi-parkings</h2>
        <ul class="space-y-3 text-sm text-on-surface-variant">
          <li>Tableau de bord et analytique globale.</li>
          <li>Cartographie complete des parkings.</li>
          <li>Controle des utilisateurs et des acces.</li>
        </ul>
      </div>
    </div>
  </section>
</template>
