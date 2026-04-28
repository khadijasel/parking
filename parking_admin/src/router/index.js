import { createRouter, createWebHistory } from 'vue-router'
import AdminLayout from '@/layouts/AdminLayout.vue'
import OwnerLayout from '@/layouts/OwnerLayout.vue'
import { homePathForRole, loginPathForRole, readStoredSession } from '@/stores/auth'
import AccessControlView from '@/views/admin/AccessControlView.vue'
import AnalyticsView from '@/views/admin/AnalyticsView.vue'
import DashboardView from '@/views/admin/DashboardView.vue'
import LiveMapView from '@/views/admin/LiveMapView.vue'
import AdminLoginView from '@/views/auth/AdminLoginView.vue'
import OwnerLoginView from '@/views/auth/OwnerLoginView.vue'
import OwnerLiveMapView from '@/views/owner/OwnerLiveMapView.vue'
import OwnParkingAdminView from '@/views/owner/OwnParkingAdminView.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      component: AdminLayout,
      meta: {
        requiresAuth: true,
        role: 'admin',
      },
      children: [
        {
          path: '',
          redirect: '/dashboard',
        },
        {
          path: 'dashboard',
          name: 'dashboard',
          component: DashboardView,
        },
        {
          path: 'analytics',
          name: 'analytics',
          component: AnalyticsView,
        },
        {
          path: 'live-map',
          name: 'live-map',
          component: LiveMapView,
        },
        {
          path: 'access-control',
          name: 'access-control',
          component: AccessControlView,
        },
      ],
    },
    {
      path: '/owner',
      component: OwnerLayout,
      meta: {
        requiresAuth: true,
        role: 'owner',
      },
      children: [
        {
          path: '',
          redirect: '/owner/my-parking',
        },
        {
          path: 'my-parking',
          name: 'owner-my-parking',
          component: OwnParkingAdminView,
        },
        {
          path: 'live-map',
          name: 'owner-live-map',
          component: OwnerLiveMapView,
        },
      ],
    },
    {
      path: '/auth',
      children: [
        {
          path: '',
          redirect: '/auth/admin',
        },
        {
          path: 'admin',
          name: 'auth-admin',
          component: AdminLoginView,
          meta: {
            guestOnly: true,
            role: 'admin',
          },
        },
        {
          path: 'owner',
          name: 'auth-owner',
          component: OwnerLoginView,
          meta: {
            guestOnly: true,
            role: 'owner',
          },
        },
      ],
    },
    {
      path: '/my-parking-admin',
      redirect: '/owner/my-parking',
    },
    {
      path: '/:pathMatch(.*)*',
      redirect: '/auth/admin',
    },
  ],
})

router.beforeEach((to) => {
  const session = readStoredSession()
  const currentRole = session?.role ?? ''

  const requiresAuth = Boolean(to.meta.requiresAuth)
  const guestOnly = Boolean(to.meta.guestOnly)
  const routeRole = String(to.meta.role ?? '').trim().toLowerCase()

  if (guestOnly) {
    if (currentRole) {
      return homePathForRole(currentRole)
    }

    return true
  }

  if (!requiresAuth) {
    return true
  }

  if (!currentRole) {
    const loginPath = loginPathForRole(routeRole)

    return {
      path: loginPath,
      query: {
        redirect: to.fullPath,
      },
    }
  }

  if (routeRole && currentRole !== routeRole) {
    return homePathForRole(currentRole)
  }

  return true
})

export default router
