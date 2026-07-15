package com.finbit.fiuadapter.webservice;

import com.finbit.fiuadapter.webservice.service.consentinit.ConsentInitServiceImpl;
import com.finbit.fiuadapter.webservice.utils.Base64Decoder;
import com.finbit.fiuadapter.webservice.utils.DateTimeUtil;
import com.finbit.fiuadapter.webservice.utils.NullEmptyUtils;
import com.finbit.fiuadapter.webservice.utils.UUIDGenerator;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Boundary / edge-case correctness for the deterministic parsing, validation and
 * timestamp helpers the FIU adapter relies on. Every assertion drives a pure,
 * side-effect-free entry point (a static util or the stateless customer-id
 * parser) with plain POJO / primitive inputs; there is no Spring context, no
 * database and no network.
 *
 * The wider application only ever exercises these helpers on the well-formed
 * values it produces itself (canonical UUIDs, "user@aa-handle" virtual
 * addresses, midday timestamps, non-blank strings, URL-safe base64 payloads),
 * so the boundary slips asserted here — a standard-vs-URL-safe base64 decode,
 * the wrong split token, a shortened UUID pattern, a dropped whitespace-trim and
 * a 12-hour clock — never surface in ordinary use.
 */
public class FiuBoundaryTest {

    /** 2022-01-15T00:00:00.000Z */
    private static final long MIDNIGHT = 1642204800000L;
    /** 2022-01-15T13:30:45.000Z */
    private static final long AFTERNOON = 1642253445000L;

    /** A canonical RFC-4122 version-4 UUID (8-4-4-4-12 hex layout). */
    private static final String VALID_UUID = "a1b2c3d4-e5f6-4789-8abc-def012345678";

    private static ConsentInitServiceImpl parser() {
        return new ConsentInitServiceImpl();
    }

    @SafeVarargs
    private static <T> List<T> list(T... items) {
        return new ArrayList<>(Arrays.asList(items));
    }

    // ---- fail_to_pass : one per planted boundary defect ---------------------

    /** D1: the JWS/JWT payload decoder uses the URL-safe base64 alphabet. */
    @Test
    public void base64Decoder_usesUrlSafeAlphabet() throws Exception {
        // "YWE_" is the URL-safe base64 encoding of "aa?"; the URL-safe alphabet
        // uses '_' where the standard alphabet uses '/'. A URL-safe decoder
        // accepts it; a standard decoder rejects the '_'.
        assertEquals("aa?", Base64Decoder.getDecodedObject("YWE_", String.class));
    }

    /** D2: a "user@handle" virtual address resolves to the handle after '@'. */
    @Test
    public void validateCustomerId_returnsHandleAfterAtSign() throws Exception {
        assertEquals("@finvu", parser().validateCustomerId("customer123@finvu"));
    }

    /** D3: the UUID pattern accepts a full canonical 8-4-4-4-12 version-4 UUID. */
    @Test
    public void uuidValidation_acceptsCanonicalVersion4() {
        assertTrue(UUIDGenerator.regaxUUIDvalidation(VALID_UUID),
                "a canonical v4 UUID must validate");
    }

    /** D4: a whitespace-only string counts as empty. */
    @Test
    public void isNullorEmpty_treatsWhitespaceOnlyAsEmpty() {
        assertTrue(NullEmptyUtils.isNullorEmpty("   "));
    }

    /** D5: the ISO timestamp is rendered on a 24-hour clock. */
    @Test
    public void getISOTimeStamp_uses24HourClock() {
        assertEquals("2022-01-15T13:30:45.000Z", DateTimeUtil.getISOTimeStamp(AFTERNOON));
    }

    // ---- pass_to_pass : behaviour unchanged by the planted defects ----------

    @Test
    public void base64Decoder_decodesPlainAlphabet() throws Exception {
        // "YWFh" (base64 of "aaa") uses only the shared alphabet, so the URL-safe
        // and standard decoders agree; ordinary payloads decode identically.
        assertEquals("aaa", Base64Decoder.getDecodedObject("YWFh", String.class));
    }

    @Test
    public void isNull_distinguishesNullFromValue() {
        assertTrue(NullEmptyUtils.isNull(null));
        assertFalse(NullEmptyUtils.isNull("x"));
    }

    @Test
    public void isNullorEmpty_nullAndEmptyStringAreEmpty() {
        assertTrue(NullEmptyUtils.isNullorEmpty((String) null));
        assertTrue(NullEmptyUtils.isNullorEmpty(""));
    }

    @Test
    public void isNullorEmpty_literalNullStringIsEmpty() {
        assertTrue(NullEmptyUtils.isNullorEmpty("null"));
    }

    @Test
    public void isNullorEmpty_ordinaryStringIsNotEmpty() {
        assertFalse(NullEmptyUtils.isNullorEmpty("hello"));
    }

    @Test
    public void isNullorEmpty_listOverloadChecksSize() {
        assertTrue(NullEmptyUtils.isNullorEmpty(new ArrayList<String>()));
        assertFalse(NullEmptyUtils.isNullorEmpty(list("x")));
    }

    @Test
    public void uuidValidation_rejectsMalformedInput() {
        assertFalse(UUIDGenerator.regaxUUIDvalidation("not-a-uuid"));
        assertFalse(UUIDGenerator.regaxUUIDvalidation(""));
    }

    @Test
    public void uuidValidation_rejectsWrongVersionDigit() {
        // version nibble is '1', not '4' -> rejected regardless of tail length
        assertFalse(UUIDGenerator.regaxUUIDvalidation("a1b2c3d4-e5f6-1789-8abc-def012345678"));
    }

    @Test
    public void getAddedDate_zeroDeltaKeepsSameDate() {
        assertTrue(DateTimeUtil.getAddedDate(MIDNIGHT, 0, 0).startsWith("2022-01-15"));
    }

    @Test
    public void getAddedDate_addsMonthsToMonthField() {
        assertTrue(DateTimeUtil.getAddedDate(MIDNIGHT, 0, 2).startsWith("2022-03-15"));
    }

    @Test
    public void getAddedDate_addsDaysToDayField() {
        // adding 10 days to 2022-01-15 lands on 2022-01-25 (date prefix only, so
        // the co-located hour-format defect cannot perturb it)
        assertTrue(DateTimeUtil.getAddedDate(MIDNIGHT, 10, 0).startsWith("2022-01-25"));
    }

    @Test
    public void getISOTimeStamp_preservesDateMinuteAndSecond() {
        String result = DateTimeUtil.getISOTimeStamp(AFTERNOON);
        assertTrue(result.startsWith("2022-01-15T"), "got " + result);
        assertTrue(result.endsWith(":30:45.000Z"), "got " + result);
    }

    @Test
    public void validateCustomerId_nullInputReturnsNull() throws Exception {
        assertNull(parser().validateCustomerId(null));
    }

    @Test
    public void validateCustomerId_prependsAtSignToHandle() throws Exception {
        assertTrue(parser().validateCustomerId("customer123@finvu").startsWith("@"));
    }
}
