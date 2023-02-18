//! This file is auto-generated by tools/update_cpu_features.zig.

const std = @import("../std.zig");
const CpuFeature = std.Target.Cpu.Feature;
const CpuModel = std.Target.Cpu.Model;

pub const Feature = enum {
    audio,
    cabac,
    compound,
    duplex,
    hvx,
    hvx_ieee_fp,
    hvx_length128b,
    hvx_length64b,
    hvx_qfloat,
    hvxv60,
    hvxv62,
    hvxv65,
    hvxv66,
    hvxv67,
    hvxv68,
    hvxv69,
    long_calls,
    mem_noshuf,
    memops,
    noreturn_stack_elim,
    nvj,
    nvs,
    packets,
    prev65,
    reserved_r19,
    small_data,
    tinycore,
    unsafe_fp,
    v5,
    v55,
    v60,
    v62,
    v65,
    v66,
    v67,
    v68,
    v69,
    zreg,
};

pub const featureSet = CpuFeature.feature_set_fns(Feature).featureSet;
pub const featureSetHas = CpuFeature.feature_set_fns(Feature).featureSetHas;
pub const featureSetHasAny = CpuFeature.feature_set_fns(Feature).featureSetHasAny;
pub const featureSetHasAll = CpuFeature.feature_set_fns(Feature).featureSetHasAll;

pub const all_features = blk: {
    const len = @typeInfo(Feature).Enum.fields.len;
    std.debug.assert(len <= CpuFeature.Set.needed_bit_count);
    var result: [len]CpuFeature = undefined;
    result[@enumToInt(Feature.audio)] = .{
        .llvm_name = "audio",
        .description = "Hexagon Audio extension instructions",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.cabac)] = .{
        .llvm_name = "cabac",
        .description = "Emit the CABAC instruction",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.compound)] = .{
        .llvm_name = "compound",
        .description = "Use compound instructions",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.duplex)] = .{
        .llvm_name = "duplex",
        .description = "Enable generation of duplex instruction",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.hvx)] = .{
        .llvm_name = "hvx",
        .description = "Hexagon HVX instructions",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.hvx_ieee_fp)] = .{
        .llvm_name = "hvx-ieee-fp",
        .description = "Hexagon HVX IEEE floating point instructions",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.hvx_length128b)] = .{
        .llvm_name = "hvx-length128b",
        .description = "Hexagon HVX 128B instructions",
        .dependencies = featureSet(&[_]Feature{
            .hvx,
        }),
    };
    result[@enumToInt(Feature.hvx_length64b)] = .{
        .llvm_name = "hvx-length64b",
        .description = "Hexagon HVX 64B instructions",
        .dependencies = featureSet(&[_]Feature{
            .hvx,
        }),
    };
    result[@enumToInt(Feature.hvx_qfloat)] = .{
        .llvm_name = "hvx-qfloat",
        .description = "Hexagon HVX QFloating point instructions",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.hvxv60)] = .{
        .llvm_name = "hvxv60",
        .description = "Hexagon HVX instructions",
        .dependencies = featureSet(&[_]Feature{
            .hvx,
        }),
    };
    result[@enumToInt(Feature.hvxv62)] = .{
        .llvm_name = "hvxv62",
        .description = "Hexagon HVX instructions",
        .dependencies = featureSet(&[_]Feature{
            .hvxv60,
        }),
    };
    result[@enumToInt(Feature.hvxv65)] = .{
        .llvm_name = "hvxv65",
        .description = "Hexagon HVX instructions",
        .dependencies = featureSet(&[_]Feature{
            .hvxv62,
        }),
    };
    result[@enumToInt(Feature.hvxv66)] = .{
        .llvm_name = "hvxv66",
        .description = "Hexagon HVX instructions",
        .dependencies = featureSet(&[_]Feature{
            .hvxv65,
            .zreg,
        }),
    };
    result[@enumToInt(Feature.hvxv67)] = .{
        .llvm_name = "hvxv67",
        .description = "Hexagon HVX instructions",
        .dependencies = featureSet(&[_]Feature{
            .hvxv66,
        }),
    };
    result[@enumToInt(Feature.hvxv68)] = .{
        .llvm_name = "hvxv68",
        .description = "Hexagon HVX instructions",
        .dependencies = featureSet(&[_]Feature{
            .hvxv67,
        }),
    };
    result[@enumToInt(Feature.hvxv69)] = .{
        .llvm_name = "hvxv69",
        .description = "Hexagon HVX instructions",
        .dependencies = featureSet(&[_]Feature{
            .hvxv68,
        }),
    };
    result[@enumToInt(Feature.long_calls)] = .{
        .llvm_name = "long-calls",
        .description = "Use constant-extended calls",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.mem_noshuf)] = .{
        .llvm_name = "mem_noshuf",
        .description = "Supports mem_noshuf feature",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.memops)] = .{
        .llvm_name = "memops",
        .description = "Use memop instructions",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.noreturn_stack_elim)] = .{
        .llvm_name = "noreturn-stack-elim",
        .description = "Eliminate stack allocation in a noreturn function when possible",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.nvj)] = .{
        .llvm_name = "nvj",
        .description = "Support for new-value jumps",
        .dependencies = featureSet(&[_]Feature{
            .packets,
        }),
    };
    result[@enumToInt(Feature.nvs)] = .{
        .llvm_name = "nvs",
        .description = "Support for new-value stores",
        .dependencies = featureSet(&[_]Feature{
            .packets,
        }),
    };
    result[@enumToInt(Feature.packets)] = .{
        .llvm_name = "packets",
        .description = "Support for instruction packets",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.prev65)] = .{
        .llvm_name = "prev65",
        .description = "Support features deprecated in v65",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.reserved_r19)] = .{
        .llvm_name = "reserved-r19",
        .description = "Reserve register R19",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.small_data)] = .{
        .llvm_name = "small-data",
        .description = "Allow GP-relative addressing of global variables",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.tinycore)] = .{
        .llvm_name = "tinycore",
        .description = "Hexagon Tiny Core",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.unsafe_fp)] = .{
        .llvm_name = "unsafe-fp",
        .description = "Use unsafe FP math",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.v5)] = .{
        .llvm_name = "v5",
        .description = "Enable Hexagon V5 architecture",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.v55)] = .{
        .llvm_name = "v55",
        .description = "Enable Hexagon V55 architecture",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.v60)] = .{
        .llvm_name = "v60",
        .description = "Enable Hexagon V60 architecture",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.v62)] = .{
        .llvm_name = "v62",
        .description = "Enable Hexagon V62 architecture",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.v65)] = .{
        .llvm_name = "v65",
        .description = "Enable Hexagon V65 architecture",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.v66)] = .{
        .llvm_name = "v66",
        .description = "Enable Hexagon V66 architecture",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.v67)] = .{
        .llvm_name = "v67",
        .description = "Enable Hexagon V67 architecture",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.v68)] = .{
        .llvm_name = "v68",
        .description = "Enable Hexagon V68 architecture",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.v69)] = .{
        .llvm_name = "v69",
        .description = "Enable Hexagon V69 architecture",
        .dependencies = featureSet(&[_]Feature{}),
    };
    result[@enumToInt(Feature.zreg)] = .{
        .llvm_name = "zreg",
        .description = "Hexagon ZReg extension instructions",
        .dependencies = featureSet(&[_]Feature{}),
    };
    const ti = @typeInfo(Feature);
    for (&result, 0..) |*elem, i| {
        elem.index = i;
        elem.name = ti.Enum.fields[i].name;
    }
    break :blk result;
};

pub const cpu = struct {
    pub const generic = CpuModel{
        .name = "generic",
        .llvm_name = "generic",
        .features = featureSet(&[_]Feature{
            .cabac,
            .compound,
            .duplex,
            .memops,
            .nvj,
            .nvs,
            .prev65,
            .small_data,
            .v5,
            .v55,
            .v60,
        }),
    };
    pub const hexagonv5 = CpuModel{
        .name = "hexagonv5",
        .llvm_name = "hexagonv5",
        .features = featureSet(&[_]Feature{
            .cabac,
            .compound,
            .duplex,
            .memops,
            .nvj,
            .nvs,
            .prev65,
            .small_data,
            .v5,
        }),
    };
    pub const hexagonv55 = CpuModel{
        .name = "hexagonv55",
        .llvm_name = "hexagonv55",
        .features = featureSet(&[_]Feature{
            .cabac,
            .compound,
            .duplex,
            .memops,
            .nvj,
            .nvs,
            .prev65,
            .small_data,
            .v5,
            .v55,
        }),
    };
    pub const hexagonv60 = CpuModel{
        .name = "hexagonv60",
        .llvm_name = "hexagonv60",
        .features = featureSet(&[_]Feature{
            .cabac,
            .compound,
            .duplex,
            .memops,
            .nvj,
            .nvs,
            .prev65,
            .small_data,
            .v5,
            .v55,
            .v60,
        }),
    };
    pub const hexagonv62 = CpuModel{
        .name = "hexagonv62",
        .llvm_name = "hexagonv62",
        .features = featureSet(&[_]Feature{
            .cabac,
            .compound,
            .duplex,
            .memops,
            .nvj,
            .nvs,
            .prev65,
            .small_data,
            .v5,
            .v55,
            .v60,
            .v62,
        }),
    };
    pub const hexagonv65 = CpuModel{
        .name = "hexagonv65",
        .llvm_name = "hexagonv65",
        .features = featureSet(&[_]Feature{
            .cabac,
            .compound,
            .duplex,
            .mem_noshuf,
            .memops,
            .nvj,
            .nvs,
            .small_data,
            .v5,
            .v55,
            .v60,
            .v62,
            .v65,
        }),
    };
    pub const hexagonv66 = CpuModel{
        .name = "hexagonv66",
        .llvm_name = "hexagonv66",
        .features = featureSet(&[_]Feature{
            .cabac,
            .compound,
            .duplex,
            .mem_noshuf,
            .memops,
            .nvj,
            .nvs,
            .small_data,
            .v5,
            .v55,
            .v60,
            .v62,
            .v65,
            .v66,
        }),
    };
    pub const hexagonv67 = CpuModel{
        .name = "hexagonv67",
        .llvm_name = "hexagonv67",
        .features = featureSet(&[_]Feature{
            .cabac,
            .compound,
            .duplex,
            .mem_noshuf,
            .memops,
            .nvj,
            .nvs,
            .small_data,
            .v5,
            .v55,
            .v60,
            .v62,
            .v65,
            .v66,
            .v67,
        }),
    };
    pub const hexagonv67t = CpuModel{
        .name = "hexagonv67t",
        .llvm_name = "hexagonv67t",
        .features = featureSet(&[_]Feature{
            .audio,
            .compound,
            .mem_noshuf,
            .memops,
            .nvs,
            .small_data,
            .tinycore,
            .v5,
            .v55,
            .v60,
            .v62,
            .v65,
            .v66,
            .v67,
        }),
    };
    pub const hexagonv68 = CpuModel{
        .name = "hexagonv68",
        .llvm_name = "hexagonv68",
        .features = featureSet(&[_]Feature{
            .cabac,
            .compound,
            .duplex,
            .mem_noshuf,
            .memops,
            .nvj,
            .nvs,
            .small_data,
            .v5,
            .v55,
            .v60,
            .v62,
            .v65,
            .v66,
            .v67,
            .v68,
        }),
    };
    pub const hexagonv69 = CpuModel{
        .name = "hexagonv69",
        .llvm_name = "hexagonv69",
        .features = featureSet(&[_]Feature{
            .cabac,
            .compound,
            .duplex,
            .mem_noshuf,
            .memops,
            .nvj,
            .nvs,
            .small_data,
            .v5,
            .v55,
            .v60,
            .v62,
            .v65,
            .v66,
            .v67,
            .v68,
            .v69,
        }),
    };
};
