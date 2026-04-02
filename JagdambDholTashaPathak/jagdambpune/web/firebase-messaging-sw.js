importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

const firebaseConfig = {
  apiKey: 'AIzaSyDhTuSuK6hzqj0WPS88BpFjIFtcQe8Ii7o',
  authDomain: 'dhol-tasha-pathak.firebaseapp.com',
  projectId: 'dhol-tasha-pathak',
  storageBucket: 'dhol-tasha-pathak.firebasestorage.app',
  messagingSenderId: '486265337828',
  appId: '1:486265337828:web:09fabc9eadf4f6cdb2f9f1',
  measurementId: 'G-3CS6QBVXB7',
};

firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage(function(payload) {
  console.log('Background message received:', payload);

  const notification = payload.notification;
  const title = notification?.title ??
    payload.data?.notification_title ??
    payload.data?.subject ??
    payload.data?.title ??
    'Notification';
  const body = notification?.body ??
    payload.data?.message ??
    payload.data?.body ??
    payload.data?.notification_body ??
    payload.data?.text ??
    '';

  // Notify all active clients
  self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
    clientList.forEach(function(client) {
      client.postMessage(
        JSON.stringify({
          type: 'fcm_background_message',
          title: title,
          body: body,
          data: payload.data || {},
        })
      );
    });
  });

  // Show browser notification
  return self.registration.showNotification(title, {
    body: body,
    icon: '/favicon.png',
    badge: '/favicon.png',
    data: payload.data || {},
  });
});

// Notify all active clients about the message
self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(
      function(clientList) {
        for (let i = 0; i < clientList.length; i++) {
          const client = clientList[i];
          if ('focus' in client) {
            return client.focus();
          }
        }
        if (clients.openWindow) {
          return clients.openWindow('/');
        }
      }
    )
  );
});
