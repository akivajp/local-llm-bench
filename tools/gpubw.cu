// GPU ごとの VRAM の実効帯域 (デバイス内コピー) と、PCIe の転送速度 (pinned memory との H2D / D2H) を測る。
// MoE のオフロードでは、VRAM に置いた重みの読み出し (VRAM 帯域) と、RAM 側のエキスパートの転送 (PCIe) が速度を決める。
// ビルド: nvcc -O3 -o gpubw gpubw.cu   実行: ./gpubw [MiB (既定 1024)]
#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>

#define CHECK(x)                                                                        \
    do {                                                                                \
        cudaError_t e = (x);                                                            \
        if (e != cudaSuccess) {                                                         \
            std::fprintf(stderr, "%s:%d %s\n", __FILE__, __LINE__, cudaGetErrorString(e)); \
            std::exit(1);                                                               \
        }                                                                               \
    } while (0)

// 同じ転送を reps 回行い、1回あたりの秒数を返す (最初の1回は捨てる)
template <class F>
static double time_it(F f, int reps) {
    cudaEvent_t a, b;
    CHECK(cudaEventCreate(&a));
    CHECK(cudaEventCreate(&b));
    f();
    CHECK(cudaDeviceSynchronize());
    CHECK(cudaEventRecord(a));
    for (int i = 0; i < reps; i++) f();
    CHECK(cudaEventRecord(b));
    CHECK(cudaEventSynchronize(b));
    float ms = 0;
    CHECK(cudaEventElapsedTime(&ms, a, b));
    return ms / 1000.0 / reps;
}

int main(int argc, char** argv) {
    const size_t mib = argc > 1 ? std::strtoul(argv[1], nullptr, 10) : 1024;
    const size_t bytes = mib << 20;
    int n = 0;
    CHECK(cudaGetDeviceCount(&n));
    void* host = nullptr;
    CHECK(cudaHostAlloc(&host, bytes, cudaHostAllocPortable));   // pinned (全 GPU から使える)
    for (int d = 0; d < n; d++) {
        CHECK(cudaSetDevice(d));
        cudaDeviceProp p;
        CHECK(cudaGetDeviceProperties(&p, d));
        void *x = nullptr, *y = nullptr;
        CHECK(cudaMalloc(&x, bytes));
        CHECK(cudaMalloc(&y, bytes));
        CHECK(cudaMemset(x, 1, bytes));
        // デバイス内コピーは読み1 + 書き1 なので 2倍のバイト数で割る
        const double t_d2d = time_it([&] { CHECK(cudaMemcpy(y, x, bytes, cudaMemcpyDeviceToDevice)); }, 20);
        const double t_h2d = time_it([&] { CHECK(cudaMemcpy(x, host, bytes, cudaMemcpyHostToDevice)); }, 10);
        const double t_d2h = time_it([&] { CHECK(cudaMemcpy(host, x, bytes, cudaMemcpyDeviceToHost)); }, 10);
        std::printf("GPU%d %s: VRAM copy %.0f GB/s | PCIe H2D %.1f GB/s, D2H %.1f GB/s (buffer %zu MiB)\n", d,
                    p.name, 2.0 * bytes / t_d2d / 1e9, bytes / t_h2d / 1e9, bytes / t_d2h / 1e9, mib);
        CHECK(cudaFree(x));
        CHECK(cudaFree(y));
    }
    CHECK(cudaFreeHost(host));
    return 0;
}
