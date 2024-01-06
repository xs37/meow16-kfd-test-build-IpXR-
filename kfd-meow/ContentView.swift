/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 */

import SwiftUI
import KernelPatchfinder

struct ContentView: View {
    
    @State private var result: UInt64 = 0
    private var puaf_method_options = ["physpuppet", "smith", "landa"]
    @State private var puaf_method = 2
    @State private var isrunningkpf = false
    @State private var message = ""

    var body: some View {
        NavigationView {
            Form {
                if result != 0 {
                    Section {
                        VStack {
                            Text("Success!").foregroundColor(.green)
                            Text("Look at output in Xcode")
                        }.frame(minWidth: 0, maxWidth: .infinity)
                    }.listRowBackground(Color.clear)
                }
                Section {
                    Picker(selection: $puaf_method, label: Text("puaf method:")) {
                        ForEach(0 ..< puaf_method_options.count, id: \.self) {
                            Text(self.puaf_method_options[$0])
                        }
                    }.disabled(result != 0).pickerStyle(SegmentedPickerStyle())
                }
                Section {
                    HStack {
                        Button("kopen") {
                            message = ""
                            result = kpoen_bridge(UInt64(puaf_method))
                        }.disabled(result != 0).frame(minWidth: 0, maxWidth: .infinity)
                        Button("kclose") {
                            result = meow_and_kclose(result)
                        }.disabled(result == 0).frame(minWidth: 0, maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }.listRowBackground(Color.clear)
                Section {
                    HStack {
                        Button("finder") {
                            isrunningkpf.toggle()
                            message = ""
                            message = message + "\ncdevsw:                  " + String(KernelPatchfinder.running?.cdevsw ?? 0x0, radix: 16)
                            message = message + "\nptov_table:              " + String(KernelPatchfinder.running?.ptov_data?.table ?? 0x0, radix: 16)
                            message = message + "\nphysBase:                " + String(KernelPatchfinder.running?.ptov_data?.physBase ?? 0x0, radix: 16)
                            message = message + "\nphysSize:                " + String(UInt64(KernelPatchfinder.running?.ptov_data?.physBase ?? 0x0) + 0x8, radix: 16)
                            message = message + "\nvirtBase:                " + String(KernelPatchfinder.running?.ptov_data?.virtBase ?? 0x0, radix: 16)
                            message = message + "\nvn_kqfilter:             " + String(KernelPatchfinder.running?.vn_kqfilter ?? 0x0, radix: 16)
                            message = message + "\nperf_devices:            " + String(KernelPatchfinder.running?.perfmon_devices ?? 0x0, radix: 16)
                            message = message + "\nperf_dev_open:           " + String(KernelPatchfinder.running?.perfmon_dev_open ?? 0x0, radix: 16)
                            message = message + "\nvm_pages:                " + String(KernelPatchfinder.running?.vm_pages ?? 0x0, radix: 16)
                            message = message + "\nvm_page_array_beginning: " + String(KernelPatchfinder.running?.vm_page_array.beginning ?? 0x0, radix: 16)
                            message = message + "\nvm_page_array_ending:    " + String(KernelPatchfinder.running?.vm_page_array.ending ?? 0x0, radix: 16)
                            message = message + "\nvm_first_phys_ppnum:     " + String(UInt64(KernelPatchfinder.running?.vm_page_array.ending ?? 0x0) + 0x8, radix: 16)
                        }.disabled(result != 0).frame(minWidth: 0, maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }.listRowBackground(Color.clear)
            }.popover(isPresented: $isrunningkpf, arrowEdge: .bottom) {
                TextEditor(text: $message)
                    .disabled(true)
                    .font(Font(UIFont.monospacedSystemFont(ofSize: 11.0, weight: .regular)))
            }
        }
    }
}

#Preview {
    ContentView()
}