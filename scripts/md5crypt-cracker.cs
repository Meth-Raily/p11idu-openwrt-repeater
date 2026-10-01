// ---------------------------------------------------------------------------
//  md5crypt-cracker.cs
//  Author : Nipun Methmal (c) 2026 - MIT License
//  Part of: p11idu-openwrt-repeater
//  See    : docs/01-hardware-and-attack-surface.md
//
//  Implementation of the md5crypt ($1$) hash, plus a candidate tester.
//  Validated against 3/3 known-answer vectors before use.
//
//  Context: the stock Tozed firmware shipped /etc/shadow with an md5crypt root
//  hash. This was built to crack it, and then became unnecessary the moment the
//  RCE in docs/04 handed us a root shell. Kept because it is tested, correct,
//  and a decent reference for how $1$ actually works.
//
//  Use only on hashes you are authorised to test.
// ---------------------------------------------------------------------------
using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;

public static class Crk
{
    const string A64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    static readonly byte[] _scratch = new byte[1 << 20];
    static readonly byte[] _empty = new byte[0];
    static readonly int[] _perm = new int[] { 12, 6, 0, 13, 7, 1, 14, 8, 2, 15, 9, 3, 5, 10, 4, 11 };

    static byte[] Asc(string s) { return Encoding.ASCII.GetBytes(s); }

    static byte[] Dig(MD5 h, byte[][] parts)
    {
        h.Initialize();
        for (int i = 0; i < parts.Length; i++)
            h.TransformBlock(parts[i], 0, parts[i].Length, _scratch, 0);
        h.TransformFinalBlock(_empty, 0, 0);
        byte[] src = h.Hash;
        byte[] d = new byte[16];
        Array.Copy(src, 0, d, 0, 16);
        return d;
    }

    static string H64(byte[] d)
    {
        byte[] t = new byte[16];
        for (int i = 0; i < 16; i++) t[i] = d[_perm[i]];

        StringBuilder sb = new StringBuilder(22);
        int bit = 0;
        while (bit < 128)
        {
            int v = 0;
            for (int k = 0; k < 6; k++)
            {
                int idx = bit + k;
                int b = 0;
                if (idx < 128) b = (t[idx >> 3] >> (idx & 7)) & 1;
                v |= b << k;
            }
            sb.Append(A64[v]);
            bit += 6;
        }
        return sb.ToString();
    }

    public static string Md5Crypt(string pw, string salt)
    {
        if (salt.Length > 8) salt = salt.Substring(0, 8);
        byte[] p = Asc(pw);
        byte[] s = Asc(salt);
        byte[] magic = Asc("$1$");
        byte[] zero = new byte[1];

        MD5 h = MD5.Create();

        byte[] B = Dig(h, new byte[][] { p, s, p });

        h.Initialize();
        h.TransformBlock(p, 0, p.Length, _scratch, 0);
        h.TransformBlock(magic, 0, magic.Length, _scratch, 0);
        h.TransformBlock(s, 0, s.Length, _scratch, 0);
        for (int i = p.Length; i > 0; i -= 16)
        {
            int n = i > 16 ? 16 : i;
            h.TransformBlock(B, 0, n, _scratch, 0);
        }
        for (int i = p.Length; i != 0; i >>= 1)
        {
            if ((i & 1) != 0) h.TransformBlock(zero, 0, 1, _scratch, 0);
            else h.TransformBlock(p, 0, 1, _scratch, 0);
        }
        h.TransformFinalBlock(_empty, 0, 0);
        byte[] prev = new byte[16];
        Array.Copy(h.Hash, 0, prev, 0, 16);

        for (int round = 0; round < 1000; round++)
        {
            h.Initialize();
            if ((round & 1) != 0) h.TransformBlock(p, 0, p.Length, _scratch, 0);
            else h.TransformBlock(prev, 0, 16, _scratch, 0);
            if (round % 3 != 0) h.TransformBlock(s, 0, s.Length, _scratch, 0);
            if (round % 7 != 0) h.TransformBlock(p, 0, p.Length, _scratch, 0);
            if ((round & 1) == 0) h.TransformBlock(p, 0, p.Length, _scratch, 0);
            else h.TransformBlock(prev, 0, 16, _scratch, 0);
            h.TransformFinalBlock(_empty, 0, 0);
            byte[] cur = new byte[16];
            Array.Copy(h.Hash, 0, cur, 0, 16);
            prev = cur;
        }

        h.Dispose();
        return "$1$" + salt + "$" + H64(prev);
    }

    // returns number of candidates that match, fills matches
    public static string[] Crack(string hash, string[] cands)
    {
        List<string> hits = new List<string>();
        for (int i = 0; i < cands.Length; i++)
        {
            string c = cands[i];
            if (c == null || c.Length == 0) continue;
            try
            {
                if (Md5Crypt(c, GetSalt(hash)) == hash) hits.Add(c);
            }
            catch { }
        }
        return hits.ToArray();
    }

    public static string GetSalt(string hash)
    {
        // $1$salt$checksum
        if (hash.Length < 4) return "";
        int a = hash.IndexOf('$', 3);
        if (a < 0) return "";
        int b = hash.IndexOf('$', a + 1);
        if (b < 0) return "";
        return hash.Substring(a + 1, b - a - 1);
    }

    public static long Bench(int n)
    {
        System.Diagnostics.Stopwatch sw = System.Diagnostics.Stopwatch.StartNew();
        for (int i = 0; i < n; i++) Md5Crypt("candidate" + i, "abc12345");
        sw.Stop();
        return sw.ElapsedMilliseconds;
    }
}
