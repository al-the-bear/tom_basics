// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

// Writes test/vectors/go_crosscheck.json: what Go's standard library
// (crypto/mlkem, crypto/mlkem/mlkemtest, crypto/mldsa, crypto/hpke) computes
// from inputs derived deterministically from a counter, so tom_pqc's tests
// can check that it computes the same.
//
//	cd tool/go_crosscheck && go run . ../../test/vectors/go_crosscheck.json
//
// Run by hand with Go 1.27 or later when the cross-check is to be refreshed.
package main

import (
	"crypto/hpke"
	"crypto/mldsa"
	"crypto/mlkem"
	"crypto/mlkem/mlkemtest"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"runtime"
)

// derive returns n bytes of SHA-256 in counter mode over label and i: inputs
// anyone can reproduce, with no secret in them.
func derive(label string, i, n int) []byte {
	var out []byte
	for block := 0; len(out) < n; block++ {
		h := sha256.Sum256([]byte(fmt.Sprintf("tom_pqc go cross-check %s %d %d", label, i, block)))
		out = append(out, h[:]...)
	}
	return out[:n]
}

func must[T any](v T, err error) T {
	if err != nil {
		panic(err)
	}
	return v
}

func must2[A, B any](a A, b B, err error) (A, B) {
	if err != nil {
		panic(err)
	}
	return a, b
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: go run . <output.json>")
		os.Exit(2)
	}
	const n = 16
	out := map[string]any{
		"note": "Computed by tool/go_crosscheck with Go's standard library from " +
			"inputs derived by SHA-256 of a label and a counter.",
		"go": runtime.Version(),
	}

	var kem []map[string]string
	for i := range n {
		seed := derive("mlkem seed", i, 64)
		random := derive("mlkem random", i, 32)
		dk := must(mlkem.NewDecapsulationKey768(seed))
		ek := dk.EncapsulationKey()
		ss, ct := must2(mlkemtest.Encapsulate768(ek, random))
		kem = append(kem, map[string]string{
			"seed": hex.EncodeToString(seed), "ek": hex.EncodeToString(ek.Bytes()),
			"random": hex.EncodeToString(random), "ct": hex.EncodeToString(ct),
			"ss": hex.EncodeToString(ss),
		})
	}
	out["mlkem768"] = kem

	var dsa []map[string]string
	for i := range n {
		seed := derive("mldsa seed", i, 32)
		message := derive("mldsa message", i, 1+i*37)
		context := string(derive("mldsa context", i, i*7))
		sk := must(mldsa.NewPrivateKey(mldsa.MLDSA65(), seed))
		opts := new(mldsa.Options)
		opts.Context = context
		sig := must(sk.SignDeterministic(message, opts))
		dsa = append(dsa, map[string]string{
			"seed": hex.EncodeToString(seed), "pk": hex.EncodeToString(sk.PublicKey().Bytes()),
			"message": hex.EncodeToString(message), "context": hex.EncodeToString([]byte(context)),
			"signature": hex.EncodeToString(sig),
		})
	}
	out["mldsa65"] = dsa

	var xwing []map[string]string
	k := hpke.MLKEM768X25519()
	for i := range n {
		seed := derive("xwing seed", i, 32)
		info := derive("xwing info", i, 1+i)
		plaintext := derive("xwing plaintext", i, 16+i)
		sk := must(k.NewPrivateKey(seed))
		pk := sk.PublicKey()
		enc, sender := must2(hpke.NewSender(pk, hpke.HKDFSHA256(), hpke.ChaCha20Poly1305(), info))
		sealed := must(sender.Seal(nil, plaintext))
		xwing = append(xwing, map[string]string{
			"seed": hex.EncodeToString(seed), "pk": hex.EncodeToString(pk.Bytes()),
			"info": hex.EncodeToString(info), "plaintext": hex.EncodeToString(plaintext),
			"enc": hex.EncodeToString(enc), "sealed": hex.EncodeToString(sealed),
		})
	}
	out["mlkem768x25519_hpke"] = xwing

	data := must(json.MarshalIndent(out, "", " "))
	if err := os.WriteFile(os.Args[1], append(data, '\n'), 0o644); err != nil {
		panic(err)
	}
	fmt.Printf("%s: %d ML-KEM-768, %d ML-DSA-65, %d MLKEM768-X25519 cases (%s)\n",
		os.Args[1], len(kem), len(dsa), len(xwing), runtime.Version())
}
