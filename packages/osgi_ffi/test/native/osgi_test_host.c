/*
 * Copyright 2026 Toyota Connected North America
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * A stand-in for the shell, for one test.
 *
 * WHAT IS UNPROVEN WITHOUT IT
 *
 * The framework rests on a claim nothing has ever verified end to end: that a
 * bundle cannot be handed a port *id*, because Dart offers no way to turn one
 * back into a SendPort -- so the shell must post a Dart_CObject_kSendPort, and
 * the receiving isolate materialises a real, usable SendPort from it.
 *
 * Every test of that so far fakes one side. osgi_ffi's fake bindings hand the
 * transport a Dart SendPort directly, never through C. ivi-homescreen's suites
 * fake the Dart DL calls, because the real ones need a VM. So the one step that
 * actually crosses -- Dart_PostCObject_DL putting a send-port CObject into a
 * live isolate's message queue -- has no coverage at all.
 *
 * This shim closes that. It installs an IhsOsgiHost over libihs_shared, and on
 * registration posts a send-port CObject back to the bundle. The Dart side then
 * has something it can send through, and can prove it by doing so.
 *
 * WHY IT POSTS THE BUNDLE'S OWN PORT
 *
 * The shell posts the *framework* isolate's port. Here there is no framework
 * isolate, so the bundle's own port is echoed back instead. That is equally
 * good for the property under test and strictly better for the test: the Dart
 * side receives a SendPort, sends through it, and the message arrives on the
 * same ReceivePort -- so "did a usable SendPort materialise" is answered by a
 * round trip inside one isolate, with no second isolate to synchronise.
 *
 * Test-only. It is not built into anything that ships.
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "dart_api_dl.h"

#include "ihs/ihs_osgi.h"
#include "ihs/ihs_osgi_host.h"

/* The handle handed back to Dart. Its address is never dereferenced by
 * libihs_shared or by Dart -- it is a capability, and this is the cheapest
 * thing that cannot collide with NULL. */
static int g_bundle_token = 0;

static int g_dl_ready = 0;

/* Bind the DL symbol table from the address the caller supplied. Every entry
 * point does this because any of them may be the first to arrive, exactly as
 * BridgeRegistry does. */
static int EnsureDartApi(void* dart_api_dl_data) {
  if (g_dl_ready) {
    return 1;
  }
  if (dart_api_dl_data == NULL) {
    return 0;
  }
  if (Dart_InitializeApiDL(dart_api_dl_data) != 0) {
    return 0;
  }
  g_dl_ready = 1;
  return 1;
}

/* Post @send_port_id to @target_port as a SendPort object. The whole point:
 * kSendPort rather than an int64, because an integer would leave the receiver
 * with nothing it can send to. */
static int PostSendPort(const int64_t target_port, const int64_t send_port_id) {
  Dart_CObject message;
  message.type = Dart_CObject_kSendPort;
  message.value.as_send_port.id = (Dart_Port_DL)send_port_id;
  message.value.as_send_port.origin_id = 0;
  return Dart_PostCObject_DL((Dart_Port_DL)target_port, &message) ? 1 : 0;
}

static int HostRegisterFramework(void* user_data,
                                 void* dart_api_dl_data,
                                 int64_t port,
                                 size_t* out_served) {
  (void)user_data;
  if (!EnsureDartApi(dart_api_dl_data)) {
    return IHS_OSGI_ERR_DART_API;
  }
  if (port == 0) {
    return IHS_OSGI_ERR_INVALID;
  }
  if (out_served != NULL) {
    *out_served = 0;
  }
  return IHS_OSGI_OK;
}

static int HostRegisterBundle(void* user_data,
                              void* dart_api_dl_data,
                              int64_t port,
                              const char* symbolic_name,
                              IhsOsgiBundle** out_bundle) {
  (void)user_data;
  if (!EnsureDartApi(dart_api_dl_data)) {
    return IHS_OSGI_ERR_DART_API;
  }
  if (port == 0 || symbolic_name == NULL || out_bundle == NULL) {
    return IHS_OSGI_ERR_INVALID;
  }
  /* Refuse one name, so the Dart side can prove a rejection maps to the right
   * exception against a real C boundary rather than against a fake. */
  if (strcmp(symbolic_name, "com.ivi.refused") == 0) {
    return IHS_OSGI_ERR_REJECTED;
  }

  *out_bundle = (IhsOsgiBundle*)&g_bundle_token;

  /* The step under test. Echo the bundle's own port back to it as a SendPort
   * object; a failure here means the isolate's queue rejected the message. */
  if (!PostSendPort(port, port)) {
    return IHS_OSGI_ERR_REJECTED;
  }
  return IHS_OSGI_OK;
}

static int HostReportActive(void* user_data, IhsOsgiBundle* bundle) {
  (void)user_data;
  return bundle == (IhsOsgiBundle*)&g_bundle_token ? IHS_OSGI_OK
                                                   : IHS_OSGI_ERR_REJECTED;
}

static int HostReportStopped(void* user_data, IhsOsgiBundle* bundle) {
  (void)user_data;
  return bundle == (IhsOsgiBundle*)&g_bundle_token ? IHS_OSGI_OK
                                                   : IHS_OSGI_ERR_REJECTED;
}

static int HostUnregister(void* user_data, IhsOsgiBundle* bundle) {
  (void)user_data;
  (void)bundle;
  return IHS_OSGI_OK;
}

/* Installed by the Dart test through dart:ffi. Separate from the table itself
 * because ihs_osgi_set_host does not copy it -- the struct has to outlive the
 * call, so it is a file-scope static rather than a local. */
void osgi_test_host_install(void) {
  static IhsOsgiHost host;
  memset(&host, 0, sizeof(host));
  host.struct_size = sizeof(IhsOsgiHost);
  host.user_data = NULL;
  host.register_framework = &HostRegisterFramework;
  host.register_bundle = &HostRegisterBundle;
  host.report_active = &HostReportActive;
  host.report_stopped = &HostReportStopped;
  host.unregister = &HostUnregister;
  ihs_osgi_set_host(&host);
}

void osgi_test_host_uninstall(void) {
  ihs_osgi_set_host(NULL);
}
