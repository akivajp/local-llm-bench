// ホストの RAM の実効帯域を測る (STREAM の Copy / Triad 相当と、読み込みだけの Read、OpenMP)。
// LLM の推論は重みを読むだけなので Read が実態に近い。Copy / Triad は書き込み (と書く前の読み込み) を含むぶん低く出る。
// 配列は1本 2GiB × 3本 (CPU のキャッシュ (L3 128MB) より十分大きくする)。各カーネルを10回回し、最速の値を出す。
// ビルド: gcc -O3 -march=native -fopenmp -o membw membw.c   実行: OMP_NUM_THREADS=16 ./membw
#include <omp.h>
#include <stdio.h>
#include <stdlib.h>

#define N (1L << 28)   // double 2^28 個 = 2 GiB
#define REPS 10

static double best(double *t) {
    double b = t[0];
    for (int i = 1; i < REPS; i++) if (t[i] < b) b = t[i];
    return b;
}

int main(void) {
    double *a = aligned_alloc(64, N * sizeof(double));
    double *b = aligned_alloc(64, N * sizeof(double));
    double *c = aligned_alloc(64, N * sizeof(double));
    if (!a || !b || !c) { fprintf(stderr, "alloc failed\n"); return 1; }
    // 初期化も並列に行い、ページを各スレッドの近くに割り当てる (first touch)
#pragma omp parallel for schedule(static)
    for (long i = 0; i < N; i++) { a[i] = 1.0; b[i] = 2.0; c[i] = 0.0; }

    double tc[REPS], tt[REPS], tr[REPS], sum = 0.0;
    const double s = 3.0;
    for (int r = 0; r < REPS; r++) {
        double t0 = omp_get_wtime();
#pragma omp parallel for schedule(static)
        for (long i = 0; i < N; i++) c[i] = a[i];               // Copy: 読み1 + 書き1
        tc[r] = omp_get_wtime() - t0;
        t0 = omp_get_wtime();
#pragma omp parallel for schedule(static)
        for (long i = 0; i < N; i++) a[i] = b[i] + s * c[i];    // Triad: 読み2 + 書き1
        tt[r] = omp_get_wtime() - t0;
        t0 = omp_get_wtime();
        double acc = 0.0;
#pragma omp parallel for schedule(static) reduction(+ : acc)
        for (long i = 0; i < N; i++) acc += b[i];                // Read: 読み1 のみ
        tr[r] = omp_get_wtime() - t0;
        sum += acc;
    }
    const double gb = 1e9;
    printf("threads=%d  Read: %.1f GB/s  Copy: %.1f GB/s  Triad: %.1f GB/s  (check %.1f %.1f)\n", omp_get_max_threads(),
           1.0 * N * sizeof(double) / best(tr) / gb, 2.0 * N * sizeof(double) / best(tc) / gb,
           3.0 * N * sizeof(double) / best(tt) / gb, a[N / 2], sum / REPS / N);
    return 0;
}
