--
-- PostgreSQL database dump
--

-- Dumped from database version 15.3
-- Dumped by pg_dump version 15.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: schema_accounting_finance; Type: SCHEMA; Schema: -; Owner: user_accounting_finance
--

CREATE SCHEMA schema_accounting_finance;


ALTER SCHEMA schema_accounting_finance OWNER TO user_accounting_finance;

--
-- Name: schema_admin; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA schema_admin;


ALTER SCHEMA schema_admin OWNER TO postgres;

--
-- Name: schema_ap; Type: SCHEMA; Schema: -; Owner: user_ap
--

CREATE SCHEMA schema_ap;


ALTER SCHEMA schema_ap OWNER TO user_ap;

--
-- Name: schema_ar; Type: SCHEMA; Schema: -; Owner: user_ar
--

CREATE SCHEMA schema_ar;


ALTER SCHEMA schema_ar OWNER TO user_ar;

--
-- Name: schema_crm; Type: SCHEMA; Schema: -; Owner: user_crm
--

CREATE SCHEMA schema_crm;


ALTER SCHEMA schema_crm OWNER TO user_crm;

--
-- Name: schema_hrd; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA schema_hrd;


ALTER SCHEMA schema_hrd OWNER TO postgres;

--
-- Name: schema_inventory_logistics; Type: SCHEMA; Schema: -; Owner: user_inventory_logistics
--

CREATE SCHEMA schema_inventory_logistics;


ALTER SCHEMA schema_inventory_logistics OWNER TO user_inventory_logistics;

--
-- Name: schema_keycloak; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA schema_keycloak;


ALTER SCHEMA schema_keycloak OWNER TO postgres;

--
-- Name: schema_production; Type: SCHEMA; Schema: -; Owner: user_production
--

CREATE SCHEMA schema_production;


ALTER SCHEMA schema_production OWNER TO user_production;

--
-- Name: sp_generate_batch_payroll(integer, character varying); Type: PROCEDURE; Schema: schema_hrd; Owner: postgres
--

CREATE PROCEDURE schema_hrd.sp_generate_batch_payroll(IN p_period_id integer, IN p_user character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_period_status VARCHAR;
    v_start_date DATE;
    v_end_date DATE;
    
    -- 1. VARIABEL PARAMETER GLOBAL (UPDATE TERBARU)
    v_overtime_divisor NUMERIC;
    v_working_days NUMERIC;
    v_bpjs_kes_max NUMERIC;
    v_bpjs_jp_max NUMERIC;
    v_working_hours NUMERIC;
    v_late_penalty NUMERIC;
    
    -- Cursor Karyawan
    cur_emp CURSOR FOR 
        SELECT dmemp_employee_code FROM schema_hrd.hr_mst_employee WHERE dmemp_is_active = 1;
        
    v_emp_code VARCHAR;
    v_basic_salary NUMERIC;
    v_total_earnings NUMERIC;
    v_total_deductions NUMERIC;
    v_net_pay NUMERIC;
    v_payslip_id INT;
BEGIN
    -- Validasi Periode
    SELECT dper_status, dper_start_date, dper_end_date 
    INTO v_period_status, v_start_date, v_end_date
    FROM schema_hrd.hr_mst_payroll_period WHERE dper_id = p_period_id;

    IF v_period_status != 'OPEN' THEN
        RAISE EXCEPTION 'Periode Payroll tidak aktif atau sudah ditutup!';
    END IF;

    -- 2. TARIK SEMUA PARAMETER GLOBAL DARI DATABASE (UPDATE TERBARU)
    SELECT dset_value INTO v_overtime_divisor FROM schema_hrd.hr_mst_company_setting WHERE dset_code = 'OVERTIME_DIVISOR';
    SELECT dset_value INTO v_working_days FROM schema_hrd.hr_mst_company_setting WHERE dset_code = 'WORKING_DAYS_MONTH';
    SELECT dset_value INTO v_bpjs_kes_max FROM schema_hrd.hr_mst_company_setting WHERE dset_code = 'BPJS_KES_MAX_WAGE';
    SELECT dset_value INTO v_bpjs_jp_max FROM schema_hrd.hr_mst_company_setting WHERE dset_code = 'BPJS_JP_MAX_WAGE';
    SELECT dset_value INTO v_working_hours FROM schema_hrd.hr_mst_company_setting WHERE dset_code = 'WORKING_HOURS_DAY';
    SELECT dset_value INTO v_late_penalty FROM schema_hrd.hr_mst_company_setting WHERE dset_code = 'LATE_PENALTY_PER_MIN';

    -- Fallback/Default Value jika HRD belum mengisi tabel Setting
    IF v_overtime_divisor IS NULL THEN v_overtime_divisor := 173; END IF;
    IF v_working_days IS NULL THEN v_working_days := 22; END IF;
    IF v_bpjs_kes_max IS NULL THEN v_bpjs_kes_max := 12000000; END IF;
    IF v_bpjs_jp_max IS NULL THEN v_bpjs_jp_max := 10042300; END IF;
    IF v_working_hours IS NULL THEN v_working_hours := 8; END IF;
    IF v_late_penalty IS NULL THEN v_late_penalty := 0; END IF;

    -- Loop Karyawan
    OPEN cur_emp;
    LOOP
        FETCH cur_emp INTO v_emp_code;
        EXIT WHEN NOT FOUND;
        
        v_total_earnings := 0; v_total_deductions := 0;

        -- Ambil Gaji Pokok
        SELECT dmsal_basic_salary INTO v_basic_salary 
        FROM schema_hrd.hr_txn_employee_salary 
        WHERE dmsal_employee_code = v_emp_code AND dmsal_is_active = 1;

        IF v_basic_salary IS NULL THEN CONTINUE; END IF;

        -- INSERT HEADER PAYSLIP
        INSERT INTO schema_hrd.hr_txn_payslip 
            (dmps_employee_code, dper_id, dmps_period_start_date, dmps_period_end_date, dmps_payment_frequency, dmps_total_earnings, dmps_total_deductions, dmps_net_pay, dmps_status, dmps_created_by)
        VALUES 
            (v_emp_code, p_period_id, v_start_date, v_end_date, 'MONTHLY', 0, 0, 0, 'DRAFT', p_user)
        RETURNING dmps_id INTO v_payslip_id;

        -- EARNING: Gaji Pokok
        INSERT INTO schema_hrd.hr_txn_payslip_line (dmpsl_payslip_id, dmpsl_category, dmpsl_description, dmpsl_amount)
        VALUES (v_payslip_id, 'EARNING', 'Gaji Pokok', v_basic_salary);
        v_total_earnings := v_total_earnings + v_basic_salary;

        -- 3. CONTOH IMPLEMENTASI DENDA TELAT (UPDATE TERBARU)
        -- (Dalam skenario nyata, tarik total menit telat dari tabel hr_txn_attendance)
        -- DECLARE v_total_late_minutes INT := 30; -- Misal telat 30 menit sebulan
        -- DECLARE v_late_deduction NUMERIC := v_total_late_minutes * v_late_penalty;
        -- Jika v_late_deduction > 0, insert ke hr_txn_payslip_line.

        -- 4. DEDUCTION: BPJS DENGAN BATAS MAKSIMAL GAJI (CAPPING) - (UPDATE TERBARU)
        DECLARE 
            cur_bpjs CURSOR FOR SELECT dbpjs_type, dbpjs_employee_rate FROM schema_hrd.hr_mst_bpjs_setting;
            v_bpjs_type VARCHAR;
            v_bpjs_rate NUMERIC;
            v_bpjs_amount NUMERIC;
            v_bpjs_basis NUMERIC; -- Gaji dasar yang akan dikalikan persentase
        BEGIN
            OPEN cur_bpjs;
            LOOP
                FETCH cur_bpjs INTO v_bpjs_type, v_bpjs_rate;
                EXIT WHEN NOT FOUND;
                
                IF v_bpjs_rate > 0 THEN
                    -- Logika Capping (Batas Atas)
                    IF v_bpjs_type = 'KESEHATAN' AND v_basic_salary > v_bpjs_kes_max THEN
                        v_bpjs_basis := v_bpjs_kes_max;
                    ELSIF v_bpjs_type = 'JP' AND v_basic_salary > v_bpjs_jp_max THEN
                        v_bpjs_basis := v_bpjs_jp_max;
                    ELSE
                        v_bpjs_basis := v_basic_salary;
                    END IF;

                    -- Hitung menggunakan v_bpjs_basis, BUKAN v_basic_salary langsung
                    v_bpjs_amount := ROUND(v_bpjs_basis * (v_bpjs_rate / 100), 2);
                    
                    INSERT INTO schema_hrd.hr_txn_payslip_line (dmpsl_payslip_id, dmpsl_category, dmpsl_description, dmpsl_amount)
                    VALUES (v_payslip_id, 'DEDUCTION', 'BPJS ' || v_bpjs_type, v_bpjs_amount);
                    
                    v_total_deductions := v_total_deductions + v_bpjs_amount;
                END IF;
            END LOOP;
            CLOSE cur_bpjs;
        END;

        -- DEDUCTION: PPh21 Progresif
        DECLARE 
            v_pph21_amount NUMERIC := 0;
        BEGIN
            v_pph21_amount := schema_hrd.uf_calculate_pph21(v_emp_code, v_total_earnings);
            
            IF v_pph21_amount > 0 THEN
                INSERT INTO schema_hrd.hr_txn_payslip_line (dmpsl_payslip_id, dmpsl_category, dmpsl_description, dmpsl_amount)
                VALUES (v_payslip_id, 'DEDUCTION', 'Potongan PPh 21', v_pph21_amount);
                
                v_total_deductions := v_total_deductions + v_pph21_amount;
            END IF;
        END;

        -- FINALISASI UPDATE HEADER
        v_net_pay := v_total_earnings - v_total_deductions;
        
        UPDATE schema_hrd.hr_txn_payslip 
        SET dmps_total_earnings = v_total_earnings,
            dmps_total_deductions = v_total_deductions,
            dmps_net_pay = v_net_pay
        WHERE dmps_id = v_payslip_id;

    END LOOP;
    CLOSE cur_emp;
END;
$$;


ALTER PROCEDURE schema_hrd.sp_generate_batch_payroll(IN p_period_id integer, IN p_user character varying) OWNER TO postgres;

--
-- Name: uf_calculate_pph21(character varying, numeric); Type: FUNCTION; Schema: schema_hrd; Owner: postgres
--

CREATE FUNCTION schema_hrd.uf_calculate_pph21(p_emp_code character varying, p_monthly_income numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_ptkp_status VARCHAR;
    v_ptkp_amount NUMERIC; 
    v_annual_income NUMERIC;
    v_pkp NUMERIC;
    v_annual_tax NUMERIC := 0;
    v_monthly_tax NUMERIC := 0;
    
    cur_tax CURSOR FOR 
        SELECT dtax_rate, dtax_min_income, dtax_max_income 
        FROM schema_hrd.hr_mst_tax_rate 
        ORDER BY dtax_min_income ASC;
        
    v_rate NUMERIC; v_min NUMERIC; v_max NUMERIC; v_span NUMERIC;
    v_taxable_in_layer NUMERIC; v_remaining_pkp NUMERIC;
BEGIN
    -- 1. Tarik Status PTKP Karyawan dari tabel Employee Tax
    SELECT detax_ptkp_status INTO v_ptkp_status 
    FROM schema_hrd.hr_mst_employee_tax 
    WHERE detax_employee_code = p_emp_code LIMIT 1;
    
    -- 2. AMBIL NOMINAL PTKP DARI TABEL MASTER (DINAMIS!)
    SELECT dptkp_amount INTO v_ptkp_amount 
    FROM schema_hrd.hr_mst_ptkp 
    WHERE dptkp_code = v_ptkp_status;

    -- Fallback: Jika HRD salah input / belum input, set default ke TK/0 (54 Juta)
    IF v_ptkp_amount IS NULL THEN
        v_ptkp_amount := 54000000;
    END IF;
    
    -- 3. Setahunkan Gaji dan Hitung PKP
    v_annual_income := p_monthly_income * 12;
    v_pkp := v_annual_income - v_ptkp_amount;
    
    -- Jika di bawah PTKP, bebas pajak
    IF v_pkp <= 0 THEN RETURN 0; END IF;
    
    -- 4. Hitung Pajak Progresif
    v_remaining_pkp := v_pkp;
    OPEN cur_tax;
    LOOP
        FETCH cur_tax INTO v_rate, v_min, v_max;
        EXIT WHEN NOT FOUND OR v_remaining_pkp <= 0;
        
        v_span := v_max - v_min;
        IF v_max >= 999999999999 OR v_remaining_pkp <= v_span THEN
            v_taxable_in_layer := v_remaining_pkp;
        ELSE
            v_taxable_in_layer := v_span;
        END IF;
        
        v_annual_tax := v_annual_tax + (v_taxable_in_layer * (v_rate / 100));
        v_remaining_pkp := v_remaining_pkp - v_taxable_in_layer;
    END LOOP;
    CLOSE cur_tax;
    
    v_monthly_tax := v_annual_tax / 12;
    RETURN ROUND(v_monthly_tax, 2);
END;
$$;


ALTER FUNCTION schema_hrd.uf_calculate_pph21(p_emp_code character varying, p_monthly_income numeric) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: crm_lead_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.crm_lead_history (
    history_id integer NOT NULL,
    changed_at timestamp(6) without time zone,
    description text,
    lead_id integer NOT NULL,
    new_stage_id integer,
    old_stage_id integer
);


ALTER TABLE public.crm_lead_history OWNER TO postgres;

--
-- Name: crm_lead_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.crm_lead_history ALTER COLUMN history_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.crm_lead_history_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: crm_lead_source; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.crm_lead_source (
    lead_source_id integer NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE public.crm_lead_source OWNER TO postgres;

--
-- Name: crm_lead_source_lead_source_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.crm_lead_source ALTER COLUMN lead_source_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.crm_lead_source_lead_source_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: adm_log_audit; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_log_audit (
    dlog_id bigint NOT NULL,
    dlog_action character varying(20) NOT NULL,
    dlog_table_name character varying(100) NOT NULL,
    dlog_record_id character varying(100),
    dlog_old_data jsonb,
    dlog_new_data jsonb,
    dlog_ip_address character varying(45),
    dlog_user_agent text,
    dlog_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    dlog_created_by character varying(100) NOT NULL
);


ALTER TABLE schema_admin.adm_log_audit OWNER TO postgres;

--
-- Name: adm_log_audit_dlog_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_log_audit_dlog_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_log_audit_dlog_id_seq OWNER TO postgres;

--
-- Name: adm_log_audit_dlog_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_log_audit_dlog_id_seq OWNED BY schema_admin.adm_log_audit.dlog_id;


--
-- Name: adm_log_login; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_log_login (
    log_id integer NOT NULL,
    user_id integer,
    username character varying(255),
    login_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    ip_address character varying(255),
    user_agent character varying(255),
    device_id character varying(255),
    login_status character varying(255),
    company_id integer,
    remarks character varying(255)
);


ALTER TABLE schema_admin.adm_log_login OWNER TO postgres;

--
-- Name: adm_log_login_log_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_log_login_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_log_login_log_id_seq OWNER TO postgres;

--
-- Name: adm_log_login_log_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_log_login_log_id_seq OWNED BY schema_admin.adm_log_login.log_id;


--
-- Name: adm_mst_application; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_application (
    dmap_id integer NOT NULL,
    dmap_application_code character varying(50) NOT NULL,
    dmap_application_name character varying(100) NOT NULL,
    dmap_description character varying(300),
    dmap_is_active boolean DEFAULT true,
    dmap_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmap_created_by character varying(50),
    dmap_modified_datetime timestamp without time zone,
    dmap_modified_by character varying(50)
);


ALTER TABLE schema_admin.adm_mst_application OWNER TO postgres;

--
-- Name: adm_mst_application_dmap_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_mst_application_dmap_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_mst_application_dmap_id_seq OWNER TO postgres;

--
-- Name: adm_mst_application_dmap_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_mst_application_dmap_id_seq OWNED BY schema_admin.adm_mst_application.dmap_id;


--
-- Name: adm_mst_branch; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_branch (
    dmbra_id integer NOT NULL,
    dmbra_regional_id integer NOT NULL,
    dmbra_branch_code character varying(50) NOT NULL,
    dmbra_branch_name character varying(50) NOT NULL,
    dmbra_is_active numeric(38,2),
    dmbra_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmbra_created_by character varying(50),
    dmbra_modified_datetime timestamp without time zone,
    dmbra_modified_by character varying(50)
);


ALTER TABLE schema_admin.adm_mst_branch OWNER TO postgres;

--
-- Name: adm_mst_company; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_company (
    dmc_id integer NOT NULL,
    dmc_company_code character varying(50) NOT NULL,
    dmc_company_name character varying(50) NOT NULL,
    dmc_is_active numeric(38,2),
    dmc_platform_code character varying(50),
    dmc_platform_name character varying(50),
    dmc_address character varying(250),
    dmc_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmc_created_by character varying(50),
    dmc_modified_datetime timestamp without time zone,
    dmc_modified_by character varying(50),
    CONSTRAINT dge_mst_company_dmc_platform_name_check CHECK (((dmc_platform_name)::text = ANY (ARRAY[('Convensional'::character varying)::text, ('Syariah'::character varying)::text])))
);


ALTER TABLE schema_admin.adm_mst_company OWNER TO postgres;

--
-- Name: adm_mst_company_application; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_company_application (
    dmca_id integer NOT NULL,
    dmca_company_id integer NOT NULL,
    dmca_application_id integer NOT NULL,
    dmca_is_active boolean DEFAULT true,
    dmca_activated_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmca_expired_date timestamp without time zone,
    dmca_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmca_created_by character varying(50),
    dmca_modified_datetime timestamp without time zone,
    dmca_modified_by character varying(50)
);


ALTER TABLE schema_admin.adm_mst_company_application OWNER TO postgres;

--
-- Name: adm_mst_company_application_dmca_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_mst_company_application_dmca_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_mst_company_application_dmca_id_seq OWNER TO postgres;

--
-- Name: adm_mst_company_application_dmca_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_mst_company_application_dmca_id_seq OWNED BY schema_admin.adm_mst_company_application.dmca_id;


--
-- Name: adm_mst_company_dmc_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_mst_company_dmc_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_mst_company_dmc_id_seq OWNER TO postgres;

--
-- Name: adm_mst_company_dmc_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_mst_company_dmc_id_seq OWNED BY schema_admin.adm_mst_company.dmc_id;


--
-- Name: adm_mst_company_module; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_company_module (
    dmcm_id integer NOT NULL,
    dmcm_company_id integer NOT NULL,
    dmcm_module_id integer NOT NULL,
    dmcm_is_active boolean DEFAULT true,
    dmcm_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmcm_created_by character varying(50),
    dmcm_modified_datetime timestamp without time zone,
    dmcm_modified_by character varying(50)
);


ALTER TABLE schema_admin.adm_mst_company_module OWNER TO postgres;

--
-- Name: adm_mst_company_module_dmcm_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_mst_company_module_dmcm_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_mst_company_module_dmcm_id_seq OWNER TO postgres;

--
-- Name: adm_mst_company_module_dmcm_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_mst_company_module_dmcm_id_seq OWNED BY schema_admin.adm_mst_company_module.dmcm_id;


--
-- Name: adm_mst_currency; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_currency (
    dmcur_id integer NOT NULL,
    dmcur_company_id integer NOT NULL,
    dmcur_currency_code character varying(50) NOT NULL,
    dmcur_currency_name character varying(50) NOT NULL,
    dmcur_is_active numeric(38,2),
    dmcur_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmcur_created_by character varying(50),
    dmcur_modified_datetime timestamp without time zone,
    dmcur_modified_by character varying(50)
);


ALTER TABLE schema_admin.adm_mst_currency OWNER TO postgres;

--
-- Name: adm_mst_menu; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_menu (
    dmmenu_id integer NOT NULL,
    dmmenu_parent_menu_id integer,
    dmmenu_code character varying(50) NOT NULL,
    dmmenu_menu_name character varying(50) NOT NULL,
    dmmenu_menu_link character varying(50),
    dmmenu_menu_index integer,
    dmmenu_is_active integer,
    dmmenu_icon_name character varying(50),
    dmmenu_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmmenu_created_by character varying(100),
    dmmenu_modified_datetime timestamp without time zone,
    dmmenu_modified_by character varying(100),
    dmmenu_company_code character varying(50),
    dmmenu_currency_code character varying(10),
    dmmenu_module_id integer,
    dmmenu_show_in_sidemenu integer
);


ALTER TABLE schema_admin.adm_mst_menu OWNER TO postgres;

--
-- Name: adm_mst_menu_temp; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_menu_temp (
    dmmt_id integer NOT NULL,
    dmmt_menu_id integer,
    dmmt_parent_menu_id integer,
    dmmt_code character varying(50) NOT NULL,
    dmmt_menu_name character varying(50) NOT NULL,
    dmmt_menu_link character varying(50),
    dmmt_menu_index integer,
    dmmt_is_active numeric(38,2),
    dmmt_icon_name character varying(50),
    dmmt_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmmt_created_by character varying(100),
    dmmt_modified_datetime timestamp without time zone,
    dmmt_modified_by character varying(100),
    dmmt_company_code character varying(50),
    dmmt_currency_code character varying(10),
    dmmt_status character varying(50),
    dmmt_revise_reason character varying(500),
    dmmt_module_id numeric(38,2),
    dmmt_show_in_sidemenu numeric(38,2)
);


ALTER TABLE schema_admin.adm_mst_menu_temp OWNER TO postgres;

--
-- Name: adm_mst_menu_temp_dmmt_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_mst_menu_temp_dmmt_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_mst_menu_temp_dmmt_id_seq OWNER TO postgres;

--
-- Name: adm_mst_menu_temp_dmmt_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_mst_menu_temp_dmmt_id_seq OWNED BY schema_admin.adm_mst_menu_temp.dmmt_id;


--
-- Name: adm_mst_regional; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_regional (
    dmreg_id integer NOT NULL,
    dmreg_company_id integer,
    dmreg_regional_code character varying(50) NOT NULL,
    dmreg_regional_name character varying(50) NOT NULL,
    dmreg_is_active numeric(38,2),
    dmreg_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmreg_created_by character varying(50),
    dmreg_modified_datetime timestamp without time zone,
    dmreg_modified_by character varying(50)
);


ALTER TABLE schema_admin.adm_mst_regional OWNER TO postgres;

--
-- Name: adm_mst_role; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_role (
    dmrole_id integer NOT NULL,
    dmrole_role_name character varying(50) NOT NULL,
    dmrole_is_active integer,
    dmrole_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmrole_created_by character varying(100),
    dmrole_modified_datetime timestamp without time zone,
    dmrole_modified_by character varying(100),
    dmrole_company_code character varying(50),
    dmrole_currency_code character varying(10),
    dmrole_application_id integer,
    dmrole_company_id integer
);


ALTER TABLE schema_admin.adm_mst_role OWNER TO postgres;

--
-- Name: adm_mst_role_menu; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_role_menu (
    dmrm_id integer NOT NULL,
    dmrm_role_id integer NOT NULL,
    dmrm_menu_id integer NOT NULL,
    dmrm_is_view integer,
    dmrm_is_add integer,
    dmrm_is_edit integer,
    dmrm_is_delete integer,
    dmrm_is_approve integer,
    dmrm_is_active integer,
    dmrm_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmrm_created_by character varying(100),
    dmrm_modified_datetime timestamp without time zone,
    dmrm_modified_by character varying(100)
);


ALTER TABLE schema_admin.adm_mst_role_menu OWNER TO postgres;

--
-- Name: adm_mst_role_menu_dmrm_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_mst_role_menu_dmrm_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_mst_role_menu_dmrm_id_seq OWNER TO postgres;

--
-- Name: adm_mst_role_menu_dmrm_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_mst_role_menu_dmrm_id_seq OWNED BY schema_admin.adm_mst_role_menu.dmrm_id;


--
-- Name: adm_mst_role_menu_temp; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_role_menu_temp (
    dmrmt_id integer NOT NULL,
    dmrmt_role_menu_id integer,
    dmrmt_role_id integer NOT NULL,
    dmrmt_menu_id integer NOT NULL,
    dmrmt_is_view numeric(38,2),
    dmrmt_is_add numeric(38,2),
    dmrmt_is_edit numeric(38,2),
    dmrmt_is_delete numeric(38,2),
    dmrmt_is_approve numeric(38,2),
    dmrmt_is_active numeric(38,2),
    dmrmt_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmrmt_created_by character varying(100),
    dmrmt_modified_datetime timestamp without time zone,
    dmrmt_modified_by character varying(100),
    dmrmt_status character varying(50),
    dmrmt_revise_reason character varying(500),
    dmrmt_company_code character varying(50),
    dmrmt_currency_code character varying(10)
);


ALTER TABLE schema_admin.adm_mst_role_menu_temp OWNER TO postgres;

--
-- Name: adm_mst_role_menu_temp_dmrmt_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_mst_role_menu_temp_dmrmt_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_mst_role_menu_temp_dmrmt_id_seq OWNER TO postgres;

--
-- Name: adm_mst_role_menu_temp_dmrmt_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_mst_role_menu_temp_dmrmt_id_seq OWNED BY schema_admin.adm_mst_role_menu_temp.dmrmt_id;


--
-- Name: adm_mst_role_temp; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_role_temp (
    dmrt_id integer NOT NULL,
    dmrt_role_id integer,
    dmrt_role_name character varying(50) NOT NULL,
    dmrt_is_active numeric(38,2),
    dmrt_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmrt_created_by character varying(100),
    dmrt_modified_datetime timestamp without time zone,
    dmrt_modified_by character varying(100),
    dmrt_status character varying(50),
    dmrt_revise_reason character varying(500),
    dmrt_company_code character varying(50),
    dmrt_currency_code character varying(10)
);


ALTER TABLE schema_admin.adm_mst_role_temp OWNER TO postgres;

--
-- Name: adm_mst_role_temp_dmrt_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_mst_role_temp_dmrt_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_mst_role_temp_dmrt_id_seq OWNER TO postgres;

--
-- Name: adm_mst_role_temp_dmrt_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_mst_role_temp_dmrt_id_seq OWNED BY schema_admin.adm_mst_role_temp.dmrt_id;


--
-- Name: adm_mst_sub_branch; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_sub_branch (
    dmsbr_id integer NOT NULL,
    dmsbr_branch_id integer NOT NULL,
    dmsbr_sub_branch_code character varying(50) NOT NULL,
    dmsbr_sub_branch_name character varying(50) NOT NULL,
    dmsbr_is_active numeric(38,2),
    dmsbr_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmsbr_created_by character varying(50),
    dmsbr_modified_datetime timestamp without time zone,
    dmsbr_modified_by character varying(50)
);


ALTER TABLE schema_admin.adm_mst_sub_branch OWNER TO postgres;

--
-- Name: adm_mst_user_application; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_user_application (
    dmuapp_id integer NOT NULL,
    dmuapp_role_id integer,
    dmuapp_employee_code character varying(50) NOT NULL,
    dmuapp_name character varying(250) NOT NULL,
    dmuapp_username character varying(250) NOT NULL,
    dmuapp_email character varying(250),
    dmuapp_mobilephone character varying(21),
    dmuapp_is_active integer,
    dmuapp_is_login integer,
    dmuapp_login_date timestamp without time zone,
    dmuapp_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmuapp_created_by character varying(100),
    dmuapp_modified_datetime timestamp without time zone,
    dmuapp_modified_by character varying(100),
    dmuapp_logout_date timestamp without time zone,
    dmuapp_company character varying(50),
    dmuapp_currency character varying(50),
    dmuapp_regional character varying(50),
    dmuapp_branch character varying(50),
    dmuapp_subbranch character varying(50),
    dmuapp_password character varying(300),
    dmuapp_last_change_pwd timestamp without time zone,
    dmuapp_must_change_pwd boolean,
    dmuapp_application_id integer,
    dmuapp_company_id integer
);


ALTER TABLE schema_admin.adm_mst_user_application OWNER TO postgres;

--
-- Name: adm_mst_user_application_dmuapp_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_mst_user_application_dmuapp_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_mst_user_application_dmuapp_id_seq OWNER TO postgres;

--
-- Name: adm_mst_user_application_dmuapp_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_mst_user_application_dmuapp_id_seq OWNED BY schema_admin.adm_mst_user_application.dmuapp_id;


--
-- Name: adm_mst_user_application_temp; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_user_application_temp (
    dmuat_id integer NOT NULL,
    dmuat_user_id integer,
    dmuat_role_id integer,
    dmuat_name character varying(250) NOT NULL,
    dmuat_username character varying(250) NOT NULL,
    dmuat_email character varying(250),
    dmuat_mobilephone character varying(21),
    dmuat_is_active numeric(38,2),
    dmuat_is_login numeric(38,2),
    dmuat_login_date timestamp without time zone,
    dmuat_logout_date timestamp without time zone,
    dmuat_status character varying(50),
    dmuat_revise_reason character varying(500),
    dmuat_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmuat_created_by character varying(100),
    dmuat_modified_datetime timestamp without time zone,
    dmuat_modified_by character varying(100),
    dmuat_company character varying(50),
    dmuat_currency character varying(50),
    dmuat_regional character varying(50),
    dmuat_branch character varying(50),
    dmuat_subbranch character varying(50)
);


ALTER TABLE schema_admin.adm_mst_user_application_temp OWNER TO postgres;

--
-- Name: adm_mst_user_application_temp_dmuat_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_mst_user_application_temp_dmuat_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_mst_user_application_temp_dmuat_id_seq OWNER TO postgres;

--
-- Name: adm_mst_user_application_temp_dmuat_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_mst_user_application_temp_dmuat_id_seq OWNED BY schema_admin.adm_mst_user_application_temp.dmuat_id;


--
-- Name: adm_mst_user_menu; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_user_menu (
    dmum_id integer NOT NULL,
    dmum_user_id integer NOT NULL,
    dmum_menu_id integer NOT NULL,
    dmum_is_view numeric(38,2),
    dmum_is_add numeric(38,2),
    dmum_is_edit numeric(38,2),
    dmum_is_delete numeric(38,2),
    dmum_is_approve numeric(38,2),
    dmum_valid_from date,
    dmum_valid_to date,
    dmum_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmum_created_by character varying(100),
    dmum_modified_datetime timestamp without time zone,
    dmum_modified_by character varying(100),
    dmum_company_code character varying(50),
    dmum_currency_code character varying(50),
    dmrm_id integer,
    dmrm_role_id integer,
    dmrm_menu_id integer,
    dmrm_is_view integer,
    dmrm_is_add integer,
    dmrm_is_edit integer,
    dmrm_is_delete integer,
    dmrm_is_approve integer,
    dmrm_is_active integer,
    dmrm_created_datetime character varying(50),
    dmrm_created_by character varying(50),
    dmrm_modified_datetime character varying(50),
    dmrm_modified_by integer
);


ALTER TABLE schema_admin.adm_mst_user_menu OWNER TO postgres;

--
-- Name: adm_mst_user_menu_temp; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_user_menu_temp (
    dmumt_id integer NOT NULL,
    dmumt_user_menu_id integer NOT NULL,
    dmumt_user_id integer NOT NULL,
    dmumt_menu_id integer NOT NULL,
    dmumt_is_view numeric(38,2),
    dmumt_is_add numeric(38,2),
    dmumt_is_edit numeric(38,2),
    dmumt_is_delete numeric(38,2),
    dmumt_is_approve numeric(38,2),
    dmumt_is_active numeric(38,2),
    dmumt_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmumt_created_by character varying(100),
    dmumt_modified_datetime timestamp without time zone,
    dmumt_modified_by character varying(100),
    dmumt_company_code character varying(50),
    dmumt_currency_code character varying(10),
    dmumt_status character varying(50),
    dmumt_revise_reason character varying(500),
    dmumt_valid_from date,
    dmumt_valid_to date
);


ALTER TABLE schema_admin.adm_mst_user_menu_temp OWNER TO postgres;

--
-- Name: adm_mst_user_menu_temp_dmumt_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_mst_user_menu_temp_dmumt_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_mst_user_menu_temp_dmumt_id_seq OWNER TO postgres;

--
-- Name: adm_mst_user_menu_temp_dmumt_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_mst_user_menu_temp_dmumt_id_seq OWNED BY schema_admin.adm_mst_user_menu_temp.dmumt_id;


--
-- Name: adm_mst_user_role; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_mst_user_role (
    dmur_id integer NOT NULL,
    dmur_user_id integer NOT NULL,
    dmur_role_id integer NOT NULL,
    dmur_is_active numeric DEFAULT 1,
    dmur_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmur_created_by character varying(100),
    dmur_modified_datetime timestamp without time zone,
    dmur_modified_by character varying(100)
);


ALTER TABLE schema_admin.adm_mst_user_role OWNER TO postgres;

--
-- Name: adm_mst_user_role_dmur_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_mst_user_role_dmur_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_mst_user_role_dmur_id_seq OWNER TO postgres;

--
-- Name: adm_mst_user_role_dmur_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_mst_user_role_dmur_id_seq OWNED BY schema_admin.adm_mst_user_role.dmur_id;


--
-- Name: adm_sec_modules; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_sec_modules (
    dsmd_module_id integer NOT NULL,
    dsmd_module_name character varying(50),
    dsmd_app_path_url character varying(512),
    dsmd_desc character varying(300),
    dsmd_status character varying(2) DEFAULT 'A'::character varying,
    dsmd_created_by character varying(15),
    dsmd_created_date timestamp without time zone,
    dsmd_updated_by character varying(15),
    dsmd_updated_date timestamp without time zone,
    dsmd_application_id integer
);


ALTER TABLE schema_admin.adm_sec_modules OWNER TO postgres;

--
-- Name: adm_sec_user_pass_recov; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.adm_sec_user_pass_recov (
    dsup_id integer NOT NULL,
    dsup_user_id integer,
    dsup_user_name character varying(64),
    dsup_token character varying(64),
    dsup_exp timestamp without time zone NOT NULL,
    dsup_used boolean DEFAULT false,
    dsup_created_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_admin.adm_sec_user_pass_recov OWNER TO postgres;

--
-- Name: adm_sec_user_pass_recov_dsup_id_seq; Type: SEQUENCE; Schema: schema_admin; Owner: postgres
--

CREATE SEQUENCE schema_admin.adm_sec_user_pass_recov_dsup_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_admin.adm_sec_user_pass_recov_dsup_id_seq OWNER TO postgres;

--
-- Name: adm_sec_user_pass_recov_dsup_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_admin; Owner: postgres
--

ALTER SEQUENCE schema_admin.adm_sec_user_pass_recov_dsup_id_seq OWNED BY schema_admin.adm_sec_user_pass_recov.dsup_id;


--
-- Name: dge_mst_menu_inherit; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.dge_mst_menu_inherit (
    dmmi_menu_parent_id integer NOT NULL,
    dmmi_menu_child_id integer NOT NULL
);


ALTER TABLE schema_admin.dge_mst_menu_inherit OWNER TO postgres;

--
-- Name: dge_mst_user_application_device; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.dge_mst_user_application_device (
    dmuad_device_id character varying(64) NOT NULL,
    dmuad_user_id integer NOT NULL,
    dmuad_created_datetime timestamp without time zone,
    dmuad_valid_date date NOT NULL
);


ALTER TABLE schema_admin.dge_mst_user_application_device OWNER TO postgres;

--
-- Name: utl_sys_config; Type: TABLE; Schema: schema_admin; Owner: postgres
--

CREATE TABLE schema_admin.utl_sys_config (
    usc_appl character varying(50) NOT NULL,
    usc_key character varying(50) NOT NULL,
    usc_data character varying(2000),
    usc_created_date timestamp without time zone,
    usc_created_by character varying(20),
    usc_updated_date timestamp without time zone,
    usc_updated_by character varying(255)
);


ALTER TABLE schema_admin.utl_sys_config OWNER TO postgres;

--
-- Name: crm_activity; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.crm_activity (
    activity_id integer NOT NULL,
    lead_id integer,
    activity_type_id integer,
    summary character varying(200),
    note text,
    date_deadline date NOT NULL,
    user_id bigint,
    is_done boolean DEFAULT false,
    done_date timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    end_time time(6) without time zone,
    start_time time(6) without time zone,
    contact_phone character varying(20)
);


ALTER TABLE schema_crm.crm_activity OWNER TO postgres;

--
-- Name: crm_activity_activity_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.crm_activity_activity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.crm_activity_activity_id_seq OWNER TO postgres;

--
-- Name: crm_activity_activity_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.crm_activity_activity_id_seq OWNED BY schema_crm.crm_activity.activity_id;


--
-- Name: crm_activity_type; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.crm_activity_type (
    activity_type_id integer NOT NULL,
    name character varying(50) NOT NULL,
    icon character varying(50),
    is_active boolean DEFAULT true
);


ALTER TABLE schema_crm.crm_activity_type OWNER TO postgres;

--
-- Name: crm_activity_type_activity_type_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.crm_activity_type_activity_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.crm_activity_type_activity_type_id_seq OWNER TO postgres;

--
-- Name: crm_activity_type_activity_type_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.crm_activity_type_activity_type_id_seq OWNED BY schema_crm.crm_activity_type.activity_type_id;


--
-- Name: crm_competitor; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.crm_competitor (
    competitor_id integer NOT NULL,
    name character varying(150) NOT NULL,
    strength text,
    weakness text,
    is_active boolean DEFAULT true,
    website character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_crm.crm_competitor OWNER TO postgres;

--
-- Name: crm_competitor_competitor_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.crm_competitor_competitor_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.crm_competitor_competitor_id_seq OWNER TO postgres;

--
-- Name: crm_competitor_competitor_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.crm_competitor_competitor_id_seq OWNED BY schema_crm.crm_competitor.competitor_id;


--
-- Name: crm_interaction_log; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.crm_interaction_log (
    log_id integer NOT NULL,
    lead_id integer,
    user_id bigint,
    interaction_type character varying(50),
    note text,
    interaction_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    activity_id integer,
    attachment_data oid,
    attachment_name character varying(255)
);


ALTER TABLE schema_crm.crm_interaction_log OWNER TO postgres;

--
-- Name: crm_interaction_log_log_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.crm_interaction_log_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.crm_interaction_log_log_id_seq OWNER TO postgres;

--
-- Name: crm_interaction_log_log_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.crm_interaction_log_log_id_seq OWNED BY schema_crm.crm_interaction_log.log_id;


--
-- Name: crm_lead; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.crm_lead (
    lead_id integer NOT NULL,
    type character varying(20) DEFAULT 'lead'::character varying,
    name character varying(150) NOT NULL,
    partner_id integer,
    contact_name character varying(100),
    email_from character varying(100),
    phone character varying(50),
    stage_id integer,
    sales_team_id integer,
    currency_id integer,
    expected_revenue numeric(15,2) DEFAULT 0.00,
    probability numeric(5,2) DEFAULT 0.00,
    campaign_id integer,
    source_id integer,
    medium_id integer,
    date_deadline date,
    date_closed timestamp without time zone,
    lost_reason_id integer,
    description text,
    is_active boolean DEFAULT true,
    created_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    priority integer DEFAULT 0,
    contact_phone character varying(20),
    user_id bigint,
    lead_source_id integer,
    partner_contact_id integer
);


ALTER TABLE schema_crm.crm_lead OWNER TO postgres;

--
-- Name: crm_lead_history; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.crm_lead_history (
    history_id integer NOT NULL,
    lead_id integer NOT NULL,
    old_stage_id integer,
    new_stage_id integer,
    description text,
    changed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_crm.crm_lead_history OWNER TO postgres;

--
-- Name: crm_lead_history_history_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.crm_lead_history_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.crm_lead_history_history_id_seq OWNER TO postgres;

--
-- Name: crm_lead_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.crm_lead_history_history_id_seq OWNED BY schema_crm.crm_lead_history.history_id;


--
-- Name: crm_lead_lead_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.crm_lead_lead_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.crm_lead_lead_id_seq OWNER TO postgres;

--
-- Name: crm_lead_lead_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.crm_lead_lead_id_seq OWNED BY schema_crm.crm_lead.lead_id;


--
-- Name: crm_lead_source; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.crm_lead_source (
    lead_source_id integer NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE schema_crm.crm_lead_source OWNER TO postgres;

--
-- Name: crm_lead_source_lead_source_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.crm_lead_source_lead_source_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.crm_lead_source_lead_source_id_seq OWNER TO postgres;

--
-- Name: crm_lead_source_lead_source_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.crm_lead_source_lead_source_id_seq OWNED BY schema_crm.crm_lead_source.lead_source_id;


--
-- Name: crm_lost_reason; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.crm_lost_reason (
    lost_reason_id integer NOT NULL,
    name character varying(100) NOT NULL,
    is_active boolean DEFAULT true,
    description character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_crm.crm_lost_reason OWNER TO postgres;

--
-- Name: crm_lost_reason_lost_reason_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.crm_lost_reason_lost_reason_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.crm_lost_reason_lost_reason_id_seq OWNER TO postgres;

--
-- Name: crm_lost_reason_lost_reason_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.crm_lost_reason_lost_reason_id_seq OWNED BY schema_crm.crm_lost_reason.lost_reason_id;


--
-- Name: crm_monthly_target; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.crm_monthly_target (
    target_id integer NOT NULL,
    user_id bigint NOT NULL,
    target_month integer NOT NULL,
    target_year integer NOT NULL,
    target_amount numeric(15,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_crm.crm_monthly_target OWNER TO postgres;

--
-- Name: crm_monthly_target_target_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.crm_monthly_target_target_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.crm_monthly_target_target_id_seq OWNER TO postgres;

--
-- Name: crm_monthly_target_target_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.crm_monthly_target_target_id_seq OWNED BY schema_crm.crm_monthly_target.target_id;


--
-- Name: crm_stage; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.crm_stage (
    stage_id integer NOT NULL,
    name character varying(50) NOT NULL,
    sequence integer,
    is_won boolean DEFAULT false,
    is_active boolean DEFAULT true
);


ALTER TABLE schema_crm.crm_stage OWNER TO postgres;

--
-- Name: crm_stage_stage_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.crm_stage_stage_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.crm_stage_stage_id_seq OWNER TO postgres;

--
-- Name: crm_stage_stage_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.crm_stage_stage_id_seq OWNED BY schema_crm.crm_stage.stage_id;


--
-- Name: crm_ticket_conversations; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.crm_ticket_conversations (
    conversation_id integer NOT NULL,
    ticket_id integer,
    user_id bigint,
    message text NOT NULL,
    attachment_name character varying(255),
    attachment_data bytea,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_crm.crm_ticket_conversations OWNER TO postgres;

--
-- Name: crm_ticket_conversations_conversation_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.crm_ticket_conversations_conversation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.crm_ticket_conversations_conversation_id_seq OWNER TO postgres;

--
-- Name: crm_ticket_conversations_conversation_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.crm_ticket_conversations_conversation_id_seq OWNED BY schema_crm.crm_ticket_conversations.conversation_id;


--
-- Name: crm_tickets; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.crm_tickets (
    ticket_id integer NOT NULL,
    ticket_number character varying(255) NOT NULL,
    subject character varying(255) NOT NULL,
    description character varying(255),
    status character varying(255) DEFAULT 'NEW'::character varying,
    priority character varying(255) DEFAULT 'MEDIUM'::character varying,
    partner_id integer,
    assigned_to bigint,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_crm.crm_tickets OWNER TO postgres;

--
-- Name: crm_tickets_ticket_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.crm_tickets_ticket_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.crm_tickets_ticket_id_seq OWNER TO postgres;

--
-- Name: crm_tickets_ticket_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.crm_tickets_ticket_id_seq OWNED BY schema_crm.crm_tickets.ticket_id;


--
-- Name: hr_employee; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.hr_employee (
    employee_id bigint NOT NULL,
    name character varying(150) NOT NULL,
    email character varying(100),
    phone character varying(20),
    job_id bigint,
    is_sales boolean DEFAULT true
);


ALTER TABLE schema_crm.hr_employee OWNER TO postgres;

--
-- Name: hr_employee_employee_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.hr_employee_employee_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.hr_employee_employee_id_seq OWNER TO postgres;

--
-- Name: hr_employee_employee_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.hr_employee_employee_id_seq OWNED BY schema_crm.hr_employee.employee_id;


--
-- Name: hr_job; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.hr_job (
    job_id bigint NOT NULL,
    name character varying(100) NOT NULL,
    description character varying(255)
);


ALTER TABLE schema_crm.hr_job OWNER TO postgres;

--
-- Name: hr_job_job_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.hr_job_job_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.hr_job_job_id_seq OWNER TO postgres;

--
-- Name: hr_job_job_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.hr_job_job_id_seq OWNED BY schema_crm.hr_job.job_id;


--
-- Name: ir_attachment; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.ir_attachment (
    attachment_id integer NOT NULL,
    name character varying(255) NOT NULL,
    file_path text NOT NULL,
    file_type character varying(50),
    res_model character varying(50) NOT NULL,
    res_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    file_size bigint
);


ALTER TABLE schema_crm.ir_attachment OWNER TO postgres;

--
-- Name: ir_attachment_attachment_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.ir_attachment_attachment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.ir_attachment_attachment_id_seq OWNER TO postgres;

--
-- Name: ir_attachment_attachment_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.ir_attachment_attachment_id_seq OWNED BY schema_crm.ir_attachment.attachment_id;


--
-- Name: lead_competitor_rel; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.lead_competitor_rel (
    lead_id integer NOT NULL,
    competitor_id integer NOT NULL
);


ALTER TABLE schema_crm.lead_competitor_rel OWNER TO postgres;

--
-- Name: mail_message; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.mail_message (
    message_id integer NOT NULL,
    res_model character varying(50) NOT NULL,
    res_id integer NOT NULL,
    author_id integer,
    body text NOT NULL,
    message_type character varying(20),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    subject character varying(255)
);


ALTER TABLE schema_crm.mail_message OWNER TO postgres;

--
-- Name: mail_message_message_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.mail_message_message_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.mail_message_message_id_seq OWNER TO postgres;

--
-- Name: mail_message_message_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.mail_message_message_id_seq OWNED BY schema_crm.mail_message.message_id;


--
-- Name: res_currency; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.res_currency (
    currency_id integer NOT NULL,
    name character varying(10) NOT NULL,
    symbol character varying(10),
    is_active boolean DEFAULT true,
    description character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_crm.res_currency OWNER TO postgres;

--
-- Name: res_currency_currency_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.res_currency_currency_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.res_currency_currency_id_seq OWNER TO postgres;

--
-- Name: res_currency_currency_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.res_currency_currency_id_seq OWNED BY schema_crm.res_currency.currency_id;


--
-- Name: res_partner; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.res_partner (
    partner_id integer NOT NULL,
    company_type character varying(20) DEFAULT 'company'::character varying,
    parent_id integer,
    name character varying(150) NOT NULL,
    job_title character varying(100),
    email character varying(100),
    phone character varying(50),
    address text,
    is_customer boolean DEFAULT false,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    mobile character varying(50),
    website character varying(150),
    tax_id character varying(50),
    is_supplier boolean DEFAULT false,
    category_id integer
);


ALTER TABLE schema_crm.res_partner OWNER TO postgres;

--
-- Name: res_partner_category; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.res_partner_category (
    category_id integer NOT NULL,
    name character varying(50) NOT NULL,
    color_code character varying(10)
);


ALTER TABLE schema_crm.res_partner_category OWNER TO postgres;

--
-- Name: res_partner_category_category_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.res_partner_category_category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.res_partner_category_category_id_seq OWNER TO postgres;

--
-- Name: res_partner_category_category_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.res_partner_category_category_id_seq OWNED BY schema_crm.res_partner_category.category_id;


--
-- Name: res_partner_contact; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.res_partner_contact (
    contact_id integer NOT NULL,
    partner_id integer,
    name character varying(150) NOT NULL,
    job_title character varying(100),
    email character varying(100),
    phone character varying(20),
    is_primary boolean DEFAULT false
);


ALTER TABLE schema_crm.res_partner_contact OWNER TO postgres;

--
-- Name: res_partner_contact_contact_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.res_partner_contact_contact_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.res_partner_contact_contact_id_seq OWNER TO postgres;

--
-- Name: res_partner_contact_contact_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.res_partner_contact_contact_id_seq OWNED BY schema_crm.res_partner_contact.contact_id;


--
-- Name: res_partner_partner_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.res_partner_partner_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.res_partner_partner_id_seq OWNER TO postgres;

--
-- Name: res_partner_partner_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.res_partner_partner_id_seq OWNED BY schema_crm.res_partner.partner_id;


--
-- Name: res_users; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.res_users (
    user_id bigint NOT NULL,
    username character varying(50) NOT NULL,
    password character varying(255) NOT NULL,
    employee_id bigint,
    is_active boolean DEFAULT true
);


ALTER TABLE schema_crm.res_users OWNER TO postgres;

--
-- Name: res_users_user_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.res_users_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.res_users_user_id_seq OWNER TO postgres;

--
-- Name: res_users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.res_users_user_id_seq OWNED BY schema_crm.res_users.user_id;


--
-- Name: sales_targets; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.sales_targets (
    target_id bigint NOT NULL,
    period character varying(255) NOT NULL,
    user_id bigint,
    target_amount numeric(38,2) NOT NULL,
    notes character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_crm.sales_targets OWNER TO postgres;

--
-- Name: sales_targets_target_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.sales_targets_target_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.sales_targets_target_id_seq OWNER TO postgres;

--
-- Name: sales_targets_target_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.sales_targets_target_id_seq OWNED BY schema_crm.sales_targets.target_id;


--
-- Name: sales_team; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.sales_team (
    team_id integer NOT NULL,
    name character varying(100) NOT NULL,
    team_leader_id integer,
    is_active boolean DEFAULT true,
    description character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    region character varying(100),
    team_type character varying(50),
    monthly_target numeric(15,2) DEFAULT 0.00,
    commission_rate numeric(5,2) DEFAULT 0.00,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_crm.sales_team OWNER TO postgres;

--
-- Name: sales_team_team_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.sales_team_team_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.sales_team_team_id_seq OWNER TO postgres;

--
-- Name: sales_team_team_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.sales_team_team_id_seq OWNED BY schema_crm.sales_team.team_id;


--
-- Name: utm_campaign; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.utm_campaign (
    campaign_id integer NOT NULL,
    name character varying(150) NOT NULL,
    start_date date,
    end_date date,
    budget numeric(15,2) DEFAULT 0.00,
    expected_revenue numeric(15,2) DEFAULT 0.00,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    description text,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_crm.utm_campaign OWNER TO postgres;

--
-- Name: utm_campaign_campaign_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.utm_campaign_campaign_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.utm_campaign_campaign_id_seq OWNER TO postgres;

--
-- Name: utm_campaign_campaign_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.utm_campaign_campaign_id_seq OWNED BY schema_crm.utm_campaign.campaign_id;


--
-- Name: utm_medium; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.utm_medium (
    medium_id integer NOT NULL,
    name character varying(100) NOT NULL,
    is_active boolean DEFAULT true,
    description character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_crm.utm_medium OWNER TO postgres;

--
-- Name: utm_medium_medium_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.utm_medium_medium_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.utm_medium_medium_id_seq OWNER TO postgres;

--
-- Name: utm_medium_medium_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.utm_medium_medium_id_seq OWNED BY schema_crm.utm_medium.medium_id;


--
-- Name: utm_source; Type: TABLE; Schema: schema_crm; Owner: postgres
--

CREATE TABLE schema_crm.utm_source (
    source_id integer NOT NULL,
    name character varying(100) NOT NULL,
    is_active boolean DEFAULT true,
    description character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_crm.utm_source OWNER TO postgres;

--
-- Name: utm_source_source_id_seq; Type: SEQUENCE; Schema: schema_crm; Owner: postgres
--

CREATE SEQUENCE schema_crm.utm_source_source_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_crm.utm_source_source_id_seq OWNER TO postgres;

--
-- Name: utm_source_source_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_crm; Owner: postgres
--

ALTER SEQUENCE schema_crm.utm_source_source_id_seq OWNED BY schema_crm.utm_source.source_id;


--
-- Name: hr_log_salary_change; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_log_salary_change (
    dlog_id integer NOT NULL,
    dlog_employee_code character varying(255),
    dlog_old_salary numeric(38,2),
    dlog_new_salary numeric(38,2),
    dlog_changed_at timestamp without time zone DEFAULT now()
);


ALTER TABLE schema_hrd.hr_log_salary_change OWNER TO postgres;

--
-- Name: hr_log_salary_change_dlog_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_log_salary_change_dlog_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_log_salary_change_dlog_id_seq OWNER TO postgres;

--
-- Name: hr_log_salary_change_dlog_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_log_salary_change_dlog_id_seq OWNED BY schema_hrd.hr_log_salary_change.dlog_id;


--
-- Name: hr_mst_approval_flow; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_approval_flow (
    daflow_id integer NOT NULL,
    daflow_name character varying(255),
    daflow_type character varying(255)
);


ALTER TABLE schema_hrd.hr_mst_approval_flow OWNER TO postgres;

--
-- Name: hr_mst_approval_flow_daflow_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_approval_flow_daflow_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_approval_flow_daflow_id_seq OWNER TO postgres;

--
-- Name: hr_mst_approval_flow_daflow_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_approval_flow_daflow_id_seq OWNED BY schema_hrd.hr_mst_approval_flow.daflow_id;


--
-- Name: hr_mst_attendance_rule; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_attendance_rule (
    datt_rule_id integer NOT NULL,
    dcomp_id integer NOT NULL,
    datt_late_penalty numeric(38,2) DEFAULT 0,
    datt_absent_penalty numeric(38,2) DEFAULT 0,
    datt_half_day_threshold integer DEFAULT 240
);


ALTER TABLE schema_hrd.hr_mst_attendance_rule OWNER TO postgres;

--
-- Name: hr_mst_attendance_rule_datt_rule_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_attendance_rule_datt_rule_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_attendance_rule_datt_rule_id_seq OWNER TO postgres;

--
-- Name: hr_mst_attendance_rule_datt_rule_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_attendance_rule_datt_rule_id_seq OWNED BY schema_hrd.hr_mst_attendance_rule.datt_rule_id;


--
-- Name: hr_mst_bpjs_setting; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_bpjs_setting (
    dbpjs_id integer NOT NULL,
    dbpjs_type character varying(255),
    dbpjs_employee_rate numeric(38,2),
    dbpjs_company_rate numeric(38,2)
);


ALTER TABLE schema_hrd.hr_mst_bpjs_setting OWNER TO postgres;

--
-- Name: hr_mst_bpjs_setting_dbpjs_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_bpjs_setting_dbpjs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_bpjs_setting_dbpjs_id_seq OWNER TO postgres;

--
-- Name: hr_mst_bpjs_setting_dbpjs_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_bpjs_setting_dbpjs_id_seq OWNED BY schema_hrd.hr_mst_bpjs_setting.dbpjs_id;


--
-- Name: hr_mst_company_config; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_company_config (
    dcomp_id integer NOT NULL,
    dcomp_code character varying(255) NOT NULL,
    dcomp_name character varying(255) NOT NULL,
    dcomp_tax_method character varying(255) DEFAULT 'GROSS'::character varying,
    dcomp_bpjs_kes_rate numeric(38,2) DEFAULT 1.00,
    dcomp_bpjs_tk_rate numeric(38,2) DEFAULT 2.00,
    dcomp_is_active boolean DEFAULT true
);


ALTER TABLE schema_hrd.hr_mst_company_config OWNER TO postgres;

--
-- Name: hr_mst_company_config_dcomp_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_company_config_dcomp_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_company_config_dcomp_id_seq OWNER TO postgres;

--
-- Name: hr_mst_company_config_dcomp_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_company_config_dcomp_id_seq OWNED BY schema_hrd.hr_mst_company_config.dcomp_id;


--
-- Name: hr_mst_company_setting; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_company_setting (
    dset_code character varying(255) NOT NULL,
    dset_value numeric(38,2) NOT NULL,
    dset_description character varying(255)
);


ALTER TABLE schema_hrd.hr_mst_company_setting OWNER TO postgres;

--
-- Name: hr_mst_department; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_department (
    dmdep_id integer NOT NULL,
    dmdep_code character varying(255) NOT NULL,
    dmdep_name character varying(255) NOT NULL,
    dmdep_is_active integer DEFAULT 1,
    dmdep_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmdep_created_by character varying(255),
    dmdep_modified_datetime timestamp without time zone,
    dmdep_modified_by character varying(255)
);


ALTER TABLE schema_hrd.hr_mst_department OWNER TO postgres;

--
-- Name: hr_mst_department_dmdep_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_department_dmdep_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_department_dmdep_id_seq OWNER TO postgres;

--
-- Name: hr_mst_department_dmdep_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_department_dmdep_id_seq OWNED BY schema_hrd.hr_mst_department.dmdep_id;


--
-- Name: hr_mst_employee; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_employee (
    dmemp_id integer NOT NULL,
    dmemp_employee_code character varying(255) NOT NULL,
    dmemp_nik character varying(255) NOT NULL,
    dmemp_employee_name character varying(255) NOT NULL,
    dmemp_photo_path text,
    dmemp_department_id integer,
    dmemp_position_id integer,
    dmemp_manager_id integer,
    dmemp_alamat character varying(255),
    dmemp_no_telp character varying(255),
    dmemp_email character varying(255),
    dmemp_gender_id character varying(255),
    dmemp_birth_date date,
    dmemp_is_active integer DEFAULT 1,
    dmemp_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmemp_created_by character varying(255),
    dmemp_modified_datetime timestamp without time zone,
    dmemp_modified_by character varying(255),
    dmemp_grade_id integer,
    dcomp_id integer
);


ALTER TABLE schema_hrd.hr_mst_employee OWNER TO postgres;

--
-- Name: hr_mst_employee_dmemp_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_employee_dmemp_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_employee_dmemp_id_seq OWNER TO postgres;

--
-- Name: hr_mst_employee_dmemp_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_employee_dmemp_id_seq OWNED BY schema_hrd.hr_mst_employee.dmemp_id;


--
-- Name: hr_mst_employee_payroll_config; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_employee_payroll_config (
    depc_id integer NOT NULL,
    depc_employee_code character varying(255) NOT NULL,
    depc_is_bpjs_kes boolean DEFAULT true,
    depc_is_bpjs_tk boolean DEFAULT true,
    depc_is_taxable boolean DEFAULT true,
    depc_is_overtime_eligible boolean DEFAULT true
);


ALTER TABLE schema_hrd.hr_mst_employee_payroll_config OWNER TO postgres;

--
-- Name: hr_mst_employee_payroll_config_depc_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_employee_payroll_config_depc_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_employee_payroll_config_depc_id_seq OWNER TO postgres;

--
-- Name: hr_mst_employee_payroll_config_depc_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_employee_payroll_config_depc_id_seq OWNED BY schema_hrd.hr_mst_employee_payroll_config.depc_id;


--
-- Name: hr_mst_employee_tax; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_employee_tax (
    detax_id integer NOT NULL,
    detax_employee_code character varying(255),
    detax_npwp character varying(255),
    detax_ptkp_status character varying(255)
);


ALTER TABLE schema_hrd.hr_mst_employee_tax OWNER TO postgres;

--
-- Name: hr_mst_employee_tax_detax_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_employee_tax_detax_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_employee_tax_detax_id_seq OWNER TO postgres;

--
-- Name: hr_mst_employee_tax_detax_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_employee_tax_detax_id_seq OWNED BY schema_hrd.hr_mst_employee_tax.detax_id;


--
-- Name: hr_mst_formula; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_formula (
    dform_id integer NOT NULL,
    dform_code character varying(255) NOT NULL,
    dform_name character varying(255) NOT NULL,
    dform_expression character varying(255) NOT NULL,
    dform_description text
);


ALTER TABLE schema_hrd.hr_mst_formula OWNER TO postgres;

--
-- Name: hr_mst_formula_dform_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_formula_dform_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_formula_dform_id_seq OWNER TO postgres;

--
-- Name: hr_mst_formula_dform_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_formula_dform_id_seq OWNED BY schema_hrd.hr_mst_formula.dform_id;


--
-- Name: hr_mst_holiday; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_holiday (
    dmhol_id integer NOT NULL,
    dmhol_date date NOT NULL,
    dmhol_description character varying(255) NOT NULL,
    dmhol_is_active integer DEFAULT 1,
    dmhol_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmhol_created_by character varying(255)
);


ALTER TABLE schema_hrd.hr_mst_holiday OWNER TO postgres;

--
-- Name: hr_mst_holiday_dmhol_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_holiday_dmhol_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_holiday_dmhol_id_seq OWNER TO postgres;

--
-- Name: hr_mst_holiday_dmhol_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_holiday_dmhol_id_seq OWNED BY schema_hrd.hr_mst_holiday.dmhol_id;


--
-- Name: hr_mst_job_grade; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_job_grade (
    dgrade_id integer NOT NULL,
    dgrade_name character varying(255),
    dgrade_min_salary numeric(38,2),
    dgrade_max_salary numeric(38,2)
);


ALTER TABLE schema_hrd.hr_mst_job_grade OWNER TO postgres;

--
-- Name: hr_mst_job_grade_dgrade_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_job_grade_dgrade_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_job_grade_dgrade_id_seq OWNER TO postgres;

--
-- Name: hr_mst_job_grade_dgrade_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_job_grade_dgrade_id_seq OWNED BY schema_hrd.hr_mst_job_grade.dgrade_id;


--
-- Name: hr_mst_leave_type; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_leave_type (
    dmlty_id integer NOT NULL,
    dmlty_code character varying(255) NOT NULL,
    dmlty_name character varying(255) NOT NULL,
    dmlty_default_days integer DEFAULT 0 NOT NULL,
    dmlty_is_active integer DEFAULT 1,
    dmlty_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmlty_created_by character varying(255)
);


ALTER TABLE schema_hrd.hr_mst_leave_type OWNER TO postgres;

--
-- Name: hr_mst_leave_type_dmlty_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_leave_type_dmlty_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_leave_type_dmlty_id_seq OWNER TO postgres;

--
-- Name: hr_mst_leave_type_dmlty_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_leave_type_dmlty_id_seq OWNED BY schema_hrd.hr_mst_leave_type.dmlty_id;


--
-- Name: hr_mst_loan_type; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_loan_type (
    dloant_id integer NOT NULL,
    dloant_code character varying(255) NOT NULL,
    dloant_name character varying(255) NOT NULL,
    dloant_interest_rate numeric(38,2) DEFAULT 0.00,
    dloant_max_tenor integer NOT NULL,
    dloant_is_active boolean DEFAULT true
);


ALTER TABLE schema_hrd.hr_mst_loan_type OWNER TO postgres;

--
-- Name: hr_mst_loan_type_dloant_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_loan_type_dloant_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_loan_type_dloant_id_seq OWNER TO postgres;

--
-- Name: hr_mst_loan_type_dloant_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_loan_type_dloant_id_seq OWNED BY schema_hrd.hr_mst_loan_type.dloant_id;


--
-- Name: hr_mst_payroll_period; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_payroll_period (
    dper_id integer NOT NULL,
    dper_code character varying(255),
    dper_name character varying(255),
    dper_start_date date,
    dper_end_date date,
    dper_status character varying(255),
    dper_created_datetime timestamp without time zone DEFAULT now(),
    dper_created_by character varying(255),
    dper_attendance_start_date date,
    dper_attendance_end_date date,
    dper_pay_date date
);


ALTER TABLE schema_hrd.hr_mst_payroll_period OWNER TO postgres;

--
-- Name: hr_mst_payroll_period_dper_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_payroll_period_dper_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_payroll_period_dper_id_seq OWNER TO postgres;

--
-- Name: hr_mst_payroll_period_dper_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_payroll_period_dper_id_seq OWNED BY schema_hrd.hr_mst_payroll_period.dper_id;


--
-- Name: hr_mst_payroll_rule; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_payroll_rule (
    drule_id integer NOT NULL,
    drule_name character varying(255),
    drule_type character varying(255),
    drule_formula text,
    drule_is_active boolean DEFAULT true,
    drule_created_datetime timestamp without time zone DEFAULT now()
);


ALTER TABLE schema_hrd.hr_mst_payroll_rule OWNER TO postgres;

--
-- Name: hr_mst_payroll_rule_drule_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_payroll_rule_drule_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_payroll_rule_drule_id_seq OWNER TO postgres;

--
-- Name: hr_mst_payroll_rule_drule_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_payroll_rule_drule_id_seq OWNED BY schema_hrd.hr_mst_payroll_rule.drule_id;


--
-- Name: hr_mst_position; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_position (
    dmpos_id integer NOT NULL,
    dmpos_code character varying(255) NOT NULL,
    dmpos_name character varying(255) NOT NULL,
    dmpos_is_active integer DEFAULT 1,
    dmpos_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmpos_created_by character varying(255),
    dmpos_modified_datetime timestamp without time zone,
    dmpos_modified_by character varying(255)
);


ALTER TABLE schema_hrd.hr_mst_position OWNER TO postgres;

--
-- Name: hr_mst_position_dmpos_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_position_dmpos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_position_dmpos_id_seq OWNER TO postgres;

--
-- Name: hr_mst_position_dmpos_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_position_dmpos_id_seq OWNED BY schema_hrd.hr_mst_position.dmpos_id;


--
-- Name: hr_mst_ptkp; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_ptkp (
    dptkp_id integer NOT NULL,
    dptkp_code character varying(255) NOT NULL,
    dptkp_amount numeric(38,2) NOT NULL,
    dptkp_description character varying(255)
);


ALTER TABLE schema_hrd.hr_mst_ptkp OWNER TO postgres;

--
-- Name: hr_mst_ptkp_dptkp_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_ptkp_dptkp_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_ptkp_dptkp_id_seq OWNER TO postgres;

--
-- Name: hr_mst_ptkp_dptkp_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_ptkp_dptkp_id_seq OWNED BY schema_hrd.hr_mst_ptkp.dptkp_id;


--
-- Name: hr_mst_salary_component; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_salary_component (
    dmsc_id integer NOT NULL,
    dmsc_code character varying(255) NOT NULL,
    dmsc_name character varying(255) NOT NULL,
    dmsc_category character varying(255) NOT NULL,
    dmsc_type character varying(255) NOT NULL,
    dmsc_is_taxable integer DEFAULT 1,
    dmsc_is_bpjs integer DEFAULT 1,
    dmsc_is_active integer DEFAULT 1,
    dmsc_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmsc_created_by character varying(255)
);


ALTER TABLE schema_hrd.hr_mst_salary_component OWNER TO postgres;

--
-- Name: hr_mst_salary_component_dmsc_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_salary_component_dmsc_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_salary_component_dmsc_id_seq OWNER TO postgres;

--
-- Name: hr_mst_salary_component_dmsc_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_salary_component_dmsc_id_seq OWNED BY schema_hrd.hr_mst_salary_component.dmsc_id;


--
-- Name: hr_mst_shift; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_shift (
    dshift_id integer NOT NULL,
    dshift_name character varying(255),
    dshift_start_time time without time zone,
    dshift_end_time time without time zone,
    dshift_is_night boolean DEFAULT false,
    dshift_created_datetime timestamp without time zone DEFAULT now()
);


ALTER TABLE schema_hrd.hr_mst_shift OWNER TO postgres;

--
-- Name: hr_mst_shift_dshift_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_shift_dshift_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_shift_dshift_id_seq OWNER TO postgres;

--
-- Name: hr_mst_shift_dshift_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_shift_dshift_id_seq OWNED BY schema_hrd.hr_mst_shift.dshift_id;


--
-- Name: hr_mst_tax_rate; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_mst_tax_rate (
    dtax_id integer NOT NULL,
    dtax_name character varying(255),
    dtax_rate numeric(38,2),
    dtax_min_income numeric(38,2),
    dtax_max_income numeric(38,2)
);


ALTER TABLE schema_hrd.hr_mst_tax_rate OWNER TO postgres;

--
-- Name: hr_mst_tax_rate_dtax_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_mst_tax_rate_dtax_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_mst_tax_rate_dtax_id_seq OWNER TO postgres;

--
-- Name: hr_mst_tax_rate_dtax_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_mst_tax_rate_dtax_id_seq OWNED BY schema_hrd.hr_mst_tax_rate.dtax_id;


--
-- Name: hr_txn_approval; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_approval (
    dapp_id integer NOT NULL,
    dapp_ref_id integer,
    dapp_ref_type character varying(255),
    dapp_approver character varying(255),
    dapp_status character varying(255),
    dapp_approved_date timestamp without time zone
);


ALTER TABLE schema_hrd.hr_txn_approval OWNER TO postgres;

--
-- Name: hr_txn_approval_dapp_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_approval_dapp_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_approval_dapp_id_seq OWNER TO postgres;

--
-- Name: hr_txn_approval_dapp_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_approval_dapp_id_seq OWNED BY schema_hrd.hr_txn_approval.dapp_id;


--
-- Name: hr_txn_attendance; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_attendance (
    dmatn_id bigint NOT NULL,
    dmatn_employee_code character varying(255) NOT NULL,
    dmatn_date date NOT NULL,
    dmatn_clock_in timestamp without time zone,
    dmatn_clock_out timestamp without time zone,
    dmatn_work_hours numeric(38,2),
    dmatn_status character varying(255),
    dmatn_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_hrd.hr_txn_attendance OWNER TO postgres;

--
-- Name: hr_txn_attendance_dmatn_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_attendance_dmatn_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_attendance_dmatn_id_seq OWNER TO postgres;

--
-- Name: hr_txn_attendance_dmatn_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_attendance_dmatn_id_seq OWNED BY schema_hrd.hr_txn_attendance.dmatn_id;


--
-- Name: hr_txn_career_history; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_career_history (
    dmcar_id integer NOT NULL,
    dmcar_employee_code character varying(255) NOT NULL,
    dmcar_type character varying(255) NOT NULL,
    dmcar_old_department_id integer,
    dmcar_new_department_id integer NOT NULL,
    dmcar_old_position_id integer,
    dmcar_new_position_id integer NOT NULL,
    dmcar_effective_date date NOT NULL,
    dmcar_reason text,
    dmcar_status character varying(255) DEFAULT 'APPROVED'::character varying,
    dmcar_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmcar_created_by character varying(255)
);


ALTER TABLE schema_hrd.hr_txn_career_history OWNER TO postgres;

--
-- Name: hr_txn_career_history_dmcar_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_career_history_dmcar_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_career_history_dmcar_id_seq OWNER TO postgres;

--
-- Name: hr_txn_career_history_dmcar_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_career_history_dmcar_id_seq OWNED BY schema_hrd.hr_txn_career_history.dmcar_id;


--
-- Name: hr_txn_contract; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_contract (
    dmcon_id integer NOT NULL,
    dmcon_employee_code character varying(255) NOT NULL,
    dmcon_contract_no character varying(255) NOT NULL,
    dmcon_employment_type character varying(255) NOT NULL,
    dmcon_start_date date NOT NULL,
    dmcon_end_date date,
    dmcon_status character varying(255) DEFAULT 'ACTIVE'::character varying NOT NULL,
    dmcon_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmcon_created_by character varying(255),
    dmcon_modified_datetime timestamp without time zone,
    dmcon_modified_by character varying(100)
);


ALTER TABLE schema_hrd.hr_txn_contract OWNER TO postgres;

--
-- Name: hr_txn_contract_dmcon_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_contract_dmcon_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_contract_dmcon_id_seq OWNER TO postgres;

--
-- Name: hr_txn_contract_dmcon_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_contract_dmcon_id_seq OWNED BY schema_hrd.hr_txn_contract.dmcon_id;


--
-- Name: hr_txn_document; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_document (
    dmdoc_id integer NOT NULL,
    dmdoc_employee_code character varying(255) NOT NULL,
    dmdoc_type character varying(255) NOT NULL,
    dmdoc_no character varying(255),
    dmdoc_file_path character varying(255) NOT NULL,
    dmdoc_expiry_date date,
    dmdoc_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmdoc_created_by character varying(255)
);


ALTER TABLE schema_hrd.hr_txn_document OWNER TO postgres;

--
-- Name: hr_txn_document_dmdoc_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_document_dmdoc_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_document_dmdoc_id_seq OWNER TO postgres;

--
-- Name: hr_txn_document_dmdoc_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_document_dmdoc_id_seq OWNED BY schema_hrd.hr_txn_document.dmdoc_id;


--
-- Name: hr_txn_employee_payroll_rule; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_employee_payroll_rule (
    depr_id integer NOT NULL,
    depr_employee_code character varying(255),
    depr_rule_id integer
);


ALTER TABLE schema_hrd.hr_txn_employee_payroll_rule OWNER TO postgres;

--
-- Name: hr_txn_employee_payroll_rule_depr_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_employee_payroll_rule_depr_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_employee_payroll_rule_depr_id_seq OWNER TO postgres;

--
-- Name: hr_txn_employee_payroll_rule_depr_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_employee_payroll_rule_depr_id_seq OWNED BY schema_hrd.hr_txn_employee_payroll_rule.depr_id;


--
-- Name: hr_txn_employee_salary; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_employee_salary (
    dmsal_id integer NOT NULL,
    dmsal_employee_code character varying(255) NOT NULL,
    dmsal_basic_salary numeric(38,2) DEFAULT 0 NOT NULL,
    dmsal_bank_name character varying(255),
    dmsal_bank_account_no character varying(255),
    dmsal_effective_start_date date NOT NULL,
    dmsal_effective_end_date date,
    dmsal_is_active integer DEFAULT 1,
    dmsal_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmsal_created_by character varying(255),
    dmsal_payment_frequency character varying(255) DEFAULT 'MONTHLY'::character varying NOT NULL
);


ALTER TABLE schema_hrd.hr_txn_employee_salary OWNER TO postgres;

--
-- Name: hr_txn_employee_salary_detail; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_employee_salary_detail (
    dmsald_id integer NOT NULL,
    dmsald_salary_id integer NOT NULL,
    dmsald_component_id integer NOT NULL,
    dmsald_amount numeric(38,2) DEFAULT 0 NOT NULL
);


ALTER TABLE schema_hrd.hr_txn_employee_salary_detail OWNER TO postgres;

--
-- Name: hr_txn_employee_salary_detail_dmsald_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_employee_salary_detail_dmsald_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_employee_salary_detail_dmsald_id_seq OWNER TO postgres;

--
-- Name: hr_txn_employee_salary_detail_dmsald_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_employee_salary_detail_dmsald_id_seq OWNED BY schema_hrd.hr_txn_employee_salary_detail.dmsald_id;


--
-- Name: hr_txn_employee_salary_dmsal_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_employee_salary_dmsal_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_employee_salary_dmsal_id_seq OWNER TO postgres;

--
-- Name: hr_txn_employee_salary_dmsal_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_employee_salary_dmsal_id_seq OWNED BY schema_hrd.hr_txn_employee_salary.dmsal_id;


--
-- Name: hr_txn_employee_shift; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_employee_shift (
    deshift_id integer NOT NULL,
    deshift_employee_code character varying(255),
    deshift_shift_id integer,
    deshift_date date,
    deshift_created_datetime timestamp without time zone DEFAULT now()
);


ALTER TABLE schema_hrd.hr_txn_employee_shift OWNER TO postgres;

--
-- Name: hr_txn_employee_shift_deshift_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_employee_shift_deshift_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_employee_shift_deshift_id_seq OWNER TO postgres;

--
-- Name: hr_txn_employee_shift_deshift_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_employee_shift_deshift_id_seq OWNED BY schema_hrd.hr_txn_employee_shift.deshift_id;


--
-- Name: hr_txn_leave_balance; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_leave_balance (
    dmlbal_id integer NOT NULL,
    dmlbal_employee_code character varying(255) NOT NULL,
    dmlbal_leave_type_id integer NOT NULL,
    dmlbal_period_year integer NOT NULL,
    dmlbal_allocated_days numeric(38,2) DEFAULT 0 NOT NULL,
    dmlbal_used_days numeric(38,2) DEFAULT 0 NOT NULL,
    dmlbal_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE schema_hrd.hr_txn_leave_balance OWNER TO postgres;

--
-- Name: hr_txn_leave_balance_dmlbal_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_leave_balance_dmlbal_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_leave_balance_dmlbal_id_seq OWNER TO postgres;

--
-- Name: hr_txn_leave_balance_dmlbal_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_leave_balance_dmlbal_id_seq OWNED BY schema_hrd.hr_txn_leave_balance.dmlbal_id;


--
-- Name: hr_txn_leave_request; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_leave_request (
    dmlreq_id integer NOT NULL,
    dmlreq_employee_code character varying(255) NOT NULL,
    dmlreq_leave_type_id integer NOT NULL,
    dmlreq_start_date date NOT NULL,
    dmlreq_end_date date NOT NULL,
    dmlreq_total_days numeric(38,2) NOT NULL,
    dmlreq_reason character varying(255),
    dmlreq_status character varying(255) DEFAULT 'DRAFT'::character varying NOT NULL,
    dmlreq_approved_by character varying(255),
    dmlreq_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmlreq_created_by character varying(255),
    dmlreq_modified_datetime timestamp without time zone,
    dmlreq_modified_by character varying(255)
);


ALTER TABLE schema_hrd.hr_txn_leave_request OWNER TO postgres;

--
-- Name: hr_txn_leave_request_dmlreq_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_leave_request_dmlreq_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_leave_request_dmlreq_id_seq OWNER TO postgres;

--
-- Name: hr_txn_leave_request_dmlreq_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_leave_request_dmlreq_id_seq OWNED BY schema_hrd.hr_txn_leave_request.dmlreq_id;


--
-- Name: hr_txn_loan; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_loan (
    dmlon_id bigint NOT NULL,
    dmlon_employee_code character varying(255) NOT NULL,
    dmlon_loan_date date NOT NULL,
    dmlon_total_amount numeric(38,2) NOT NULL,
    dmlon_installment_amount numeric(38,2) NOT NULL,
    dmlon_tenor integer NOT NULL,
    dmlon_remaining_balance numeric(38,2) NOT NULL,
    dmlon_status character varying(255) DEFAULT 'ACTIVE'::character varying,
    dmlon_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmlon_created_by character varying(255),
    dloant_id integer
);


ALTER TABLE schema_hrd.hr_txn_loan OWNER TO postgres;

--
-- Name: hr_txn_loan_dmlon_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_loan_dmlon_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_loan_dmlon_id_seq OWNER TO postgres;

--
-- Name: hr_txn_loan_dmlon_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_loan_dmlon_id_seq OWNED BY schema_hrd.hr_txn_loan.dmlon_id;


--
-- Name: hr_txn_overtime; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_overtime (
    dmovt_id integer NOT NULL,
    dmovt_employee_code character varying(255) NOT NULL,
    dmovt_attendance_id bigint,
    dmovt_request_date date NOT NULL,
    dmovt_start_time timestamp without time zone NOT NULL,
    dmovt_end_time timestamp without time zone NOT NULL,
    dmovt_total_hours numeric(38,2) NOT NULL,
    dmovt_reason character varying(255) NOT NULL,
    dmovt_status character varying(255) DEFAULT 'DRAFT'::character varying NOT NULL,
    dmovt_approved_by character varying(255),
    dmovt_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmovt_created_by character varying(255),
    dmovt_modified_datetime timestamp without time zone,
    dmovt_modified_by character varying(255),
    dmovt_is_holiday integer DEFAULT 0
);


ALTER TABLE schema_hrd.hr_txn_overtime OWNER TO postgres;

--
-- Name: hr_txn_overtime_dmovt_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_overtime_dmovt_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_overtime_dmovt_id_seq OWNER TO postgres;

--
-- Name: hr_txn_overtime_dmovt_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_overtime_dmovt_id_seq OWNED BY schema_hrd.hr_txn_overtime.dmovt_id;


--
-- Name: hr_txn_payslip; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_payslip (
    dmps_id bigint NOT NULL,
    dmps_employee_code character varying(255) NOT NULL,
    dmps_total_earnings numeric(38,2) DEFAULT 0 NOT NULL,
    dmps_total_deductions numeric(38,2) DEFAULT 0 NOT NULL,
    dmps_net_pay numeric(38,2) DEFAULT 0 NOT NULL,
    dmps_status character varying(255) DEFAULT 'DRAFT'::character varying NOT NULL,
    dmps_created_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dmps_created_by character varying(255),
    dmps_period_start_date date NOT NULL,
    dmps_period_end_date date NOT NULL,
    dmps_payment_frequency character varying(255) DEFAULT 'MONTHLY'::character varying NOT NULL,
    dper_id integer
);


ALTER TABLE schema_hrd.hr_txn_payslip OWNER TO postgres;

--
-- Name: hr_txn_payslip_dmps_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_payslip_dmps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_payslip_dmps_id_seq OWNER TO postgres;

--
-- Name: hr_txn_payslip_dmps_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_payslip_dmps_id_seq OWNED BY schema_hrd.hr_txn_payslip.dmps_id;


--
-- Name: hr_txn_payslip_line; Type: TABLE; Schema: schema_hrd; Owner: postgres
--

CREATE TABLE schema_hrd.hr_txn_payslip_line (
    dmpsl_id integer NOT NULL,
    dmpsl_payslip_id bigint NOT NULL,
    dmpsl_component_id integer,
    dmpsl_category character varying(255) NOT NULL,
    dmpsl_description character varying(255) NOT NULL,
    dmpsl_amount numeric(38,2) DEFAULT 0 NOT NULL
);


ALTER TABLE schema_hrd.hr_txn_payslip_line OWNER TO postgres;

--
-- Name: hr_txn_payslip_line_dmpsl_id_seq; Type: SEQUENCE; Schema: schema_hrd; Owner: postgres
--

CREATE SEQUENCE schema_hrd.hr_txn_payslip_line_dmpsl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE schema_hrd.hr_txn_payslip_line_dmpsl_id_seq OWNER TO postgres;

--
-- Name: hr_txn_payslip_line_dmpsl_id_seq; Type: SEQUENCE OWNED BY; Schema: schema_hrd; Owner: postgres
--

ALTER SEQUENCE schema_hrd.hr_txn_payslip_line_dmpsl_id_seq OWNED BY schema_hrd.hr_txn_payslip_line.dmpsl_id;


--
-- Name: admin_event_entity; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.admin_event_entity (
    id character varying(36) NOT NULL,
    admin_event_time bigint,
    realm_id character varying(255),
    operation_type character varying(255),
    auth_realm_id character varying(255),
    auth_client_id character varying(255),
    auth_user_id character varying(255),
    ip_address character varying(255),
    resource_path character varying(2550),
    representation text,
    error character varying(255),
    resource_type character varying(64),
    details_json text
);


ALTER TABLE schema_keycloak.admin_event_entity OWNER TO postgres;

--
-- Name: associated_policy; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.associated_policy (
    policy_id character varying(36) NOT NULL,
    associated_policy_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.associated_policy OWNER TO postgres;

--
-- Name: auth_session; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.auth_session (
    root_auth_session_id character varying(36) NOT NULL,
    tab_id character varying(36) NOT NULL,
    client_uuid character varying(255),
    auth_user_id character varying(255),
    "timestamp" bigint,
    version integer,
    redirect_uri text,
    action character varying(255),
    protocol character varying(255),
    client_scopes text,
    execution_status text,
    client_notes text,
    auth_notes text,
    required_actions text,
    user_session_notes text
);


ALTER TABLE schema_keycloak.auth_session OWNER TO postgres;

--
-- Name: authentication_execution; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.authentication_execution (
    id character varying(36) NOT NULL,
    alias character varying(255),
    authenticator character varying(36),
    realm_id character varying(36),
    flow_id character varying(36),
    requirement integer,
    priority integer,
    authenticator_flow boolean DEFAULT false NOT NULL,
    auth_flow_id character varying(36),
    auth_config character varying(36)
);


ALTER TABLE schema_keycloak.authentication_execution OWNER TO postgres;

--
-- Name: authentication_flow; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.authentication_flow (
    id character varying(36) NOT NULL,
    alias character varying(255),
    description character varying(255),
    realm_id character varying(36),
    provider_id character varying(36) DEFAULT 'basic-flow'::character varying NOT NULL,
    top_level boolean DEFAULT false NOT NULL,
    built_in boolean DEFAULT false NOT NULL
);


ALTER TABLE schema_keycloak.authentication_flow OWNER TO postgres;

--
-- Name: authenticator_config; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.authenticator_config (
    id character varying(36) NOT NULL,
    alias character varying(255),
    realm_id character varying(36)
);


ALTER TABLE schema_keycloak.authenticator_config OWNER TO postgres;

--
-- Name: authenticator_config_entry; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.authenticator_config_entry (
    authenticator_id character varying(36) NOT NULL,
    value text,
    name character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.authenticator_config_entry OWNER TO postgres;

--
-- Name: broker_link; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.broker_link (
    identity_provider character varying(255) NOT NULL,
    storage_provider_id character varying(255),
    realm_id character varying(36) NOT NULL,
    broker_user_id character varying(255),
    broker_username character varying(255),
    token text,
    user_id character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.broker_link OWNER TO postgres;

--
-- Name: client; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.client (
    id character varying(36) NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    full_scope_allowed boolean DEFAULT false NOT NULL,
    client_id character varying(255),
    not_before integer,
    public_client boolean DEFAULT false NOT NULL,
    secret character varying(255),
    base_url character varying(255),
    bearer_only boolean DEFAULT false NOT NULL,
    management_url character varying(255),
    surrogate_auth_required boolean DEFAULT false NOT NULL,
    realm_id character varying(36),
    protocol character varying(255),
    node_rereg_timeout integer DEFAULT 0,
    frontchannel_logout boolean DEFAULT false NOT NULL,
    consent_required boolean DEFAULT false NOT NULL,
    name character varying(255),
    service_accounts_enabled boolean DEFAULT false NOT NULL,
    client_authenticator_type character varying(255),
    root_url character varying(255),
    description character varying(255),
    registration_token character varying(255),
    standard_flow_enabled boolean DEFAULT true NOT NULL,
    implicit_flow_enabled boolean DEFAULT false NOT NULL,
    direct_access_grants_enabled boolean DEFAULT false NOT NULL,
    always_display_in_console boolean DEFAULT false NOT NULL,
    created_timestamp bigint,
    last_modified_timestamp bigint
);


ALTER TABLE schema_keycloak.client OWNER TO postgres;

--
-- Name: client_attributes; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.client_attributes (
    client_id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    value text
);


ALTER TABLE schema_keycloak.client_attributes OWNER TO postgres;

--
-- Name: client_auth_flow_bindings; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.client_auth_flow_bindings (
    client_id character varying(36) NOT NULL,
    flow_id character varying(36),
    binding_name character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.client_auth_flow_bindings OWNER TO postgres;

--
-- Name: client_initial_access; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.client_initial_access (
    id character varying(36) NOT NULL,
    realm_id character varying(36) NOT NULL,
    "timestamp" integer,
    expiration integer,
    count integer,
    remaining_count integer
);


ALTER TABLE schema_keycloak.client_initial_access OWNER TO postgres;

--
-- Name: client_node_registrations; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.client_node_registrations (
    client_id character varying(36) NOT NULL,
    value integer,
    name character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.client_node_registrations OWNER TO postgres;

--
-- Name: client_scope; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.client_scope (
    id character varying(36) NOT NULL,
    name character varying(255),
    realm_id character varying(36),
    description character varying(255),
    protocol character varying(255)
);


ALTER TABLE schema_keycloak.client_scope OWNER TO postgres;

--
-- Name: client_scope_attributes; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.client_scope_attributes (
    scope_id character varying(36) NOT NULL,
    value character varying(2048),
    name character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.client_scope_attributes OWNER TO postgres;

--
-- Name: client_scope_client; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.client_scope_client (
    client_id character varying(255) NOT NULL,
    scope_id character varying(255) NOT NULL,
    default_scope boolean DEFAULT false NOT NULL
);


ALTER TABLE schema_keycloak.client_scope_client OWNER TO postgres;

--
-- Name: client_scope_role_mapping; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.client_scope_role_mapping (
    scope_id character varying(36) NOT NULL,
    role_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.client_scope_role_mapping OWNER TO postgres;

--
-- Name: cluster_event; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.cluster_event (
    id character varying(36) NOT NULL,
    target_cluster character varying(200) NOT NULL,
    sender_cluster character varying(200) NOT NULL,
    event_data oid NOT NULL,
    created_at bigint NOT NULL
);


ALTER TABLE schema_keycloak.cluster_event OWNER TO postgres;

--
-- Name: component; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.component (
    id character varying(36) NOT NULL,
    name character varying(255),
    parent_id character varying(36),
    provider_id character varying(36),
    provider_type character varying(255),
    realm_id character varying(36),
    sub_type character varying(255)
);


ALTER TABLE schema_keycloak.component OWNER TO postgres;

--
-- Name: component_config; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.component_config (
    id character varying(36) NOT NULL,
    component_id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    value text
);


ALTER TABLE schema_keycloak.component_config OWNER TO postgres;

--
-- Name: composite_role; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.composite_role (
    composite character varying(36) NOT NULL,
    child_role character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.composite_role OWNER TO postgres;

--
-- Name: credential; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.credential (
    id character varying(36) NOT NULL,
    salt bytea,
    type character varying(255),
    user_id character varying(36),
    created_date bigint,
    user_label character varying(255),
    secret_data text,
    credential_data text,
    priority integer,
    version integer DEFAULT 0
);


ALTER TABLE schema_keycloak.credential OWNER TO postgres;

--
-- Name: databasechangelog; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.databasechangelog (
    id character varying(255) NOT NULL,
    author character varying(255) NOT NULL,
    filename character varying(255) NOT NULL,
    dateexecuted timestamp without time zone NOT NULL,
    orderexecuted integer NOT NULL,
    exectype character varying(10) NOT NULL,
    md5sum character varying(35),
    description character varying(255),
    comments character varying(255),
    tag character varying(255),
    liquibase character varying(20),
    contexts character varying(255),
    labels character varying(255),
    deployment_id character varying(10)
);


ALTER TABLE schema_keycloak.databasechangelog OWNER TO postgres;

--
-- Name: databasechangeloglock; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.databasechangeloglock (
    id integer NOT NULL,
    locked boolean NOT NULL,
    lockgranted timestamp without time zone,
    lockedby character varying(255)
);


ALTER TABLE schema_keycloak.databasechangeloglock OWNER TO postgres;

--
-- Name: default_client_scope; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.default_client_scope (
    realm_id character varying(36) NOT NULL,
    scope_id character varying(36) NOT NULL,
    default_scope boolean DEFAULT false NOT NULL
);


ALTER TABLE schema_keycloak.default_client_scope OWNER TO postgres;

--
-- Name: event_entity; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.event_entity (
    id character varying(36) NOT NULL,
    client_id character varying(255),
    details_json character varying(2550),
    error character varying(255),
    ip_address character varying(255),
    realm_id character varying(255),
    session_id character varying(255),
    event_time bigint,
    type character varying(255),
    user_id character varying(255),
    details_json_long_value text
);


ALTER TABLE schema_keycloak.event_entity OWNER TO postgres;

--
-- Name: fed_issued_ver_credential; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.fed_issued_ver_credential (
    id character varying(36) NOT NULL,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36) NOT NULL,
    ver_credential_id character varying(36) NOT NULL,
    issued_at bigint NOT NULL,
    expires_at bigint,
    client_id character varying(36),
    revision character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.fed_issued_ver_credential OWNER TO postgres;

--
-- Name: fed_user_attribute; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.fed_user_attribute (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36),
    value character varying(2024),
    long_value_hash bytea,
    long_value_hash_lower_case bytea,
    long_value text
);


ALTER TABLE schema_keycloak.fed_user_attribute OWNER TO postgres;

--
-- Name: fed_user_consent; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.fed_user_consent (
    id character varying(36) NOT NULL,
    client_id character varying(255),
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36),
    created_date bigint,
    last_updated_date bigint,
    client_storage_provider character varying(36),
    external_client_id character varying(255)
);


ALTER TABLE schema_keycloak.fed_user_consent OWNER TO postgres;

--
-- Name: fed_user_consent_cl_scope; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.fed_user_consent_cl_scope (
    user_consent_id character varying(36) NOT NULL,
    scope_id character varying(36) NOT NULL,
    parameter character varying(255) DEFAULT '#N A#'::character varying NOT NULL
);


ALTER TABLE schema_keycloak.fed_user_consent_cl_scope OWNER TO postgres;

--
-- Name: fed_user_credential; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.fed_user_credential (
    id character varying(36) NOT NULL,
    salt bytea,
    type character varying(255),
    created_date bigint,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36),
    user_label character varying(255),
    secret_data text,
    credential_data text,
    priority integer
);


ALTER TABLE schema_keycloak.fed_user_credential OWNER TO postgres;

--
-- Name: fed_user_group_membership; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.fed_user_group_membership (
    group_id character varying(36) NOT NULL,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36)
);


ALTER TABLE schema_keycloak.fed_user_group_membership OWNER TO postgres;

--
-- Name: fed_user_required_action; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.fed_user_required_action (
    required_action character varying(255) DEFAULT ' '::character varying NOT NULL,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36)
);


ALTER TABLE schema_keycloak.fed_user_required_action OWNER TO postgres;

--
-- Name: fed_user_role_mapping; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.fed_user_role_mapping (
    role_id character varying(36) NOT NULL,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36)
);


ALTER TABLE schema_keycloak.fed_user_role_mapping OWNER TO postgres;

--
-- Name: fed_user_ver_credential; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.fed_user_ver_credential (
    id character varying(36) NOT NULL,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    storage_provider_id character varying(36),
    client_scope_id character varying(36) NOT NULL,
    revision character varying(36) NOT NULL,
    user_attributes text,
    created_date bigint,
    updated_date bigint,
    version integer DEFAULT 0 NOT NULL
);


ALTER TABLE schema_keycloak.fed_user_ver_credential OWNER TO postgres;

--
-- Name: federated_identity; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.federated_identity (
    identity_provider character varying(255) NOT NULL,
    realm_id character varying(36),
    federated_user_id character varying(255),
    federated_username character varying(255),
    token text,
    user_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.federated_identity OWNER TO postgres;

--
-- Name: federated_user; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.federated_user (
    id character varying(255) NOT NULL,
    storage_provider_id character varying(255),
    realm_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.federated_user OWNER TO postgres;

--
-- Name: group_attribute; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.group_attribute (
    id character varying(36) DEFAULT 'sybase-needs-something-here'::character varying NOT NULL,
    name character varying(255) NOT NULL,
    value character varying(255),
    group_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.group_attribute OWNER TO postgres;

--
-- Name: group_role_mapping; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.group_role_mapping (
    role_id character varying(36) NOT NULL,
    group_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.group_role_mapping OWNER TO postgres;

--
-- Name: identity_provider; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.identity_provider (
    internal_id character varying(36) NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    provider_alias character varying(255),
    provider_id character varying(255),
    store_token boolean,
    authenticate_by_default boolean,
    realm_id character varying(36),
    add_token_role boolean,
    trust_email boolean,
    first_broker_login_flow_id character varying(36),
    post_broker_login_flow_id character varying(36),
    provider_display_name character varying(255),
    link_only boolean,
    organization_id character varying(255),
    hide_on_login boolean
);


ALTER TABLE schema_keycloak.identity_provider OWNER TO postgres;

--
-- Name: identity_provider_config; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.identity_provider_config (
    identity_provider_id character varying(36) NOT NULL,
    value text,
    name character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.identity_provider_config OWNER TO postgres;

--
-- Name: identity_provider_mapper; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.identity_provider_mapper (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    idp_alias character varying(255) NOT NULL,
    idp_mapper_name character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.identity_provider_mapper OWNER TO postgres;

--
-- Name: idp_mapper_config; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.idp_mapper_config (
    idp_mapper_id character varying(36) NOT NULL,
    value text,
    name character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.idp_mapper_config OWNER TO postgres;

--
-- Name: issued_ver_credential; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.issued_ver_credential (
    id character varying(36) NOT NULL,
    user_id character varying(36) NOT NULL,
    ver_credential_id character varying(36) NOT NULL,
    issued_at bigint NOT NULL,
    expires_at bigint,
    client_id character varying(36),
    revision character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.issued_ver_credential OWNER TO postgres;

--
-- Name: jgroups_ping; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.jgroups_ping (
    address character varying(200) NOT NULL,
    name character varying(200),
    cluster_name character varying(200) NOT NULL,
    ip character varying(200) NOT NULL,
    coord boolean,
    last_update bigint,
    coordinated_by character varying(200)
);


ALTER TABLE schema_keycloak.jgroups_ping OWNER TO postgres;

--
-- Name: keycloak_group; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.keycloak_group (
    id character varying(36) NOT NULL,
    name character varying(255),
    parent_group character varying(36) NOT NULL,
    realm_id character varying(36),
    type integer DEFAULT 0 NOT NULL,
    description character varying(255),
    org_id character varying(255),
    created_timestamp bigint,
    last_modified_timestamp bigint
);


ALTER TABLE schema_keycloak.keycloak_group OWNER TO postgres;

--
-- Name: keycloak_role; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.keycloak_role (
    id character varying(36) NOT NULL,
    client_realm_constraint character varying(255),
    client_role boolean DEFAULT false NOT NULL,
    description character varying(255),
    name character varying(255),
    realm_id character varying(255),
    client character varying(36),
    realm character varying(36)
);


ALTER TABLE schema_keycloak.keycloak_role OWNER TO postgres;

--
-- Name: login_failure; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.login_failure (
    realm_id character varying(36) NOT NULL,
    user_id character varying(255) NOT NULL,
    failed_login_not_before bigint DEFAULT 0,
    num_failures integer DEFAULT 0,
    num_temporary_lockouts integer DEFAULT 0,
    last_failure bigint DEFAULT 0,
    last_ip_failure character varying(255),
    num_secondary_auth_failures integer DEFAULT 0
);


ALTER TABLE schema_keycloak.login_failure OWNER TO postgres;

--
-- Name: migration_model; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.migration_model (
    id character varying(36) NOT NULL,
    version character varying(36),
    update_time bigint DEFAULT 0 NOT NULL
);


ALTER TABLE schema_keycloak.migration_model OWNER TO postgres;

--
-- Name: offline_client_session; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.offline_client_session (
    user_session_id character varying(36) NOT NULL,
    client_id character varying(255) NOT NULL,
    offline_flag character varying(4) NOT NULL,
    "timestamp" integer,
    data text,
    client_storage_provider character varying(36) DEFAULT 'local'::character varying NOT NULL,
    external_client_id character varying(255) DEFAULT 'local'::character varying NOT NULL,
    version integer DEFAULT 0,
    realm_id character varying(36)
);


ALTER TABLE schema_keycloak.offline_client_session OWNER TO postgres;

--
-- Name: offline_user_session; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.offline_user_session (
    user_session_id character varying(36) NOT NULL,
    user_id character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    created_on integer NOT NULL,
    offline_flag character varying(4) NOT NULL,
    data text,
    last_session_refresh integer DEFAULT 0 NOT NULL,
    broker_session_id character varying(1024),
    version integer DEFAULT 0,
    remember_me boolean
);


ALTER TABLE schema_keycloak.offline_user_session OWNER TO postgres;

--
-- Name: org; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.org (
    id character varying(255) NOT NULL,
    enabled boolean NOT NULL,
    realm_id character varying(255) NOT NULL,
    group_id character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    description character varying(4000),
    alias character varying(255) NOT NULL,
    redirect_url character varying(2048)
);


ALTER TABLE schema_keycloak.org OWNER TO postgres;

--
-- Name: org_domain; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.org_domain (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    verified boolean NOT NULL,
    org_id character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.org_domain OWNER TO postgres;

--
-- Name: org_invitation; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.org_invitation (
    id character varying(36) NOT NULL,
    organization_id character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    first_name character varying(255),
    last_name character varying(255),
    created_at integer NOT NULL,
    expires_at integer,
    invite_link character varying(2048)
);


ALTER TABLE schema_keycloak.org_invitation OWNER TO postgres;

--
-- Name: outbox_entry; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.outbox_entry (
    id character varying(36) NOT NULL,
    entry_kind character varying(64) NOT NULL,
    realm_id character varying(36) NOT NULL,
    owner_id character varying(64) NOT NULL,
    container_id character varying(64),
    correlation_id character varying(255) NOT NULL,
    entry_type character varying(256) NOT NULL,
    payload text NOT NULL,
    metadata text,
    status character varying(16) NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    next_attempt_at timestamp without time zone NOT NULL,
    last_error character varying(2048),
    created_at timestamp without time zone NOT NULL,
    delivered_at timestamp without time zone
);


ALTER TABLE schema_keycloak.outbox_entry OWNER TO postgres;

--
-- Name: policy_config; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.policy_config (
    policy_id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    value text
);


ALTER TABLE schema_keycloak.policy_config OWNER TO postgres;

--
-- Name: protocol_mapper; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.protocol_mapper (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    protocol character varying(255) NOT NULL,
    protocol_mapper_name character varying(255) NOT NULL,
    client_id character varying(36),
    client_scope_id character varying(36)
);


ALTER TABLE schema_keycloak.protocol_mapper OWNER TO postgres;

--
-- Name: protocol_mapper_config; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.protocol_mapper_config (
    protocol_mapper_id character varying(36) NOT NULL,
    value text,
    name character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.protocol_mapper_config OWNER TO postgres;

--
-- Name: realm; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.realm (
    id character varying(36) NOT NULL,
    access_code_lifespan integer,
    user_action_lifespan integer,
    access_token_lifespan integer,
    account_theme character varying(255),
    admin_theme character varying(255),
    email_theme character varying(255),
    enabled boolean DEFAULT false NOT NULL,
    events_enabled boolean DEFAULT false NOT NULL,
    events_expiration bigint,
    login_theme character varying(255),
    name character varying(255),
    not_before integer,
    password_policy character varying(2550),
    registration_allowed boolean DEFAULT false NOT NULL,
    remember_me boolean DEFAULT false NOT NULL,
    reset_password_allowed boolean DEFAULT false NOT NULL,
    social boolean DEFAULT false NOT NULL,
    ssl_required character varying(255),
    sso_idle_timeout integer,
    sso_max_lifespan integer,
    update_profile_on_soc_login boolean DEFAULT false NOT NULL,
    verify_email boolean DEFAULT false NOT NULL,
    master_admin_client character varying(36),
    login_lifespan integer,
    internationalization_enabled boolean DEFAULT false NOT NULL,
    default_locale character varying(255),
    reg_email_as_username boolean DEFAULT false NOT NULL,
    admin_events_enabled boolean DEFAULT false NOT NULL,
    admin_events_details_enabled boolean DEFAULT false NOT NULL,
    edit_username_allowed boolean DEFAULT false NOT NULL,
    otp_policy_counter integer DEFAULT 0,
    otp_policy_window integer DEFAULT 1,
    otp_policy_period integer DEFAULT 30,
    otp_policy_digits integer DEFAULT 6,
    otp_policy_alg character varying(36) DEFAULT 'HmacSHA1'::character varying,
    otp_policy_type character varying(36) DEFAULT 'totp'::character varying,
    browser_flow character varying(36),
    registration_flow character varying(36),
    direct_grant_flow character varying(36),
    reset_credentials_flow character varying(36),
    client_auth_flow character varying(36),
    offline_session_idle_timeout integer DEFAULT 0,
    revoke_refresh_token boolean DEFAULT false NOT NULL,
    access_token_life_implicit integer DEFAULT 0,
    login_with_email_allowed boolean DEFAULT true NOT NULL,
    duplicate_emails_allowed boolean DEFAULT false NOT NULL,
    docker_auth_flow character varying(36),
    refresh_token_max_reuse integer DEFAULT 0,
    allow_user_managed_access boolean DEFAULT false NOT NULL,
    sso_max_lifespan_remember_me integer DEFAULT 0 NOT NULL,
    sso_idle_timeout_remember_me integer DEFAULT 0 NOT NULL,
    default_role character varying(255),
    display_name character varying(255)
);


ALTER TABLE schema_keycloak.realm OWNER TO postgres;

--
-- Name: realm_attribute; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.realm_attribute (
    name character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL,
    value text
);


ALTER TABLE schema_keycloak.realm_attribute OWNER TO postgres;

--
-- Name: realm_default_groups; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.realm_default_groups (
    realm_id character varying(36) NOT NULL,
    group_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.realm_default_groups OWNER TO postgres;

--
-- Name: realm_enabled_event_types; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.realm_enabled_event_types (
    realm_id character varying(36) NOT NULL,
    value character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.realm_enabled_event_types OWNER TO postgres;

--
-- Name: realm_events_listeners; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.realm_events_listeners (
    realm_id character varying(36) NOT NULL,
    value character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.realm_events_listeners OWNER TO postgres;

--
-- Name: realm_localizations; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.realm_localizations (
    realm_id character varying(255) NOT NULL,
    locale character varying(255) NOT NULL,
    texts text NOT NULL
);


ALTER TABLE schema_keycloak.realm_localizations OWNER TO postgres;

--
-- Name: realm_required_credential; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.realm_required_credential (
    type character varying(255) NOT NULL,
    form_label character varying(255),
    input boolean DEFAULT false NOT NULL,
    secret boolean DEFAULT false NOT NULL,
    realm_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.realm_required_credential OWNER TO postgres;

--
-- Name: realm_smtp_config; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.realm_smtp_config (
    realm_id character varying(36) NOT NULL,
    value character varying(255),
    name character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.realm_smtp_config OWNER TO postgres;

--
-- Name: realm_supported_locales; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.realm_supported_locales (
    realm_id character varying(36) NOT NULL,
    value character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.realm_supported_locales OWNER TO postgres;

--
-- Name: redirect_uris; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.redirect_uris (
    client_id character varying(36) NOT NULL,
    value character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.redirect_uris OWNER TO postgres;

--
-- Name: required_action_config; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.required_action_config (
    required_action_id character varying(36) NOT NULL,
    value text,
    name character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.required_action_config OWNER TO postgres;

--
-- Name: required_action_provider; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.required_action_provider (
    id character varying(36) NOT NULL,
    alias character varying(255),
    name character varying(255),
    realm_id character varying(36),
    enabled boolean DEFAULT false NOT NULL,
    default_action boolean DEFAULT false NOT NULL,
    provider_id character varying(255),
    priority integer
);


ALTER TABLE schema_keycloak.required_action_provider OWNER TO postgres;

--
-- Name: resource_attribute; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.resource_attribute (
    id character varying(36) DEFAULT 'sybase-needs-something-here'::character varying NOT NULL,
    name character varying(255) NOT NULL,
    value character varying(255),
    resource_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.resource_attribute OWNER TO postgres;

--
-- Name: resource_policy; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.resource_policy (
    resource_id character varying(36) NOT NULL,
    policy_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.resource_policy OWNER TO postgres;

--
-- Name: resource_scope; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.resource_scope (
    resource_id character varying(36) NOT NULL,
    scope_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.resource_scope OWNER TO postgres;

--
-- Name: resource_server; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.resource_server (
    id character varying(36) NOT NULL,
    allow_rs_remote_mgmt boolean DEFAULT false NOT NULL,
    policy_enforce_mode smallint NOT NULL,
    decision_strategy smallint DEFAULT 1 NOT NULL
);


ALTER TABLE schema_keycloak.resource_server OWNER TO postgres;

--
-- Name: resource_server_perm_ticket; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.resource_server_perm_ticket (
    id character varying(36) NOT NULL,
    owner character varying(255) NOT NULL,
    requester character varying(255) NOT NULL,
    created_timestamp bigint NOT NULL,
    granted_timestamp bigint,
    resource_id character varying(36) NOT NULL,
    scope_id character varying(36),
    resource_server_id character varying(36) NOT NULL,
    policy_id character varying(36)
);


ALTER TABLE schema_keycloak.resource_server_perm_ticket OWNER TO postgres;

--
-- Name: resource_server_policy; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.resource_server_policy (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    description character varying(255),
    type character varying(255) NOT NULL,
    decision_strategy smallint,
    logic smallint,
    resource_server_id character varying(36) NOT NULL,
    owner character varying(255)
);


ALTER TABLE schema_keycloak.resource_server_policy OWNER TO postgres;

--
-- Name: resource_server_resource; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.resource_server_resource (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    type character varying(255),
    icon_uri character varying(255),
    owner character varying(255) NOT NULL,
    resource_server_id character varying(36) NOT NULL,
    owner_managed_access boolean DEFAULT false NOT NULL,
    display_name character varying(255)
);


ALTER TABLE schema_keycloak.resource_server_resource OWNER TO postgres;

--
-- Name: resource_server_scope; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.resource_server_scope (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    icon_uri character varying(255),
    resource_server_id character varying(36) NOT NULL,
    display_name character varying(255)
);


ALTER TABLE schema_keycloak.resource_server_scope OWNER TO postgres;

--
-- Name: resource_uris; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.resource_uris (
    resource_id character varying(36) NOT NULL,
    value character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.resource_uris OWNER TO postgres;

--
-- Name: revoked_token; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.revoked_token (
    id character varying(255) NOT NULL,
    expire bigint NOT NULL
);


ALTER TABLE schema_keycloak.revoked_token OWNER TO postgres;

--
-- Name: role_attribute; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.role_attribute (
    id character varying(36) NOT NULL,
    role_id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    value character varying(255)
);


ALTER TABLE schema_keycloak.role_attribute OWNER TO postgres;

--
-- Name: root_auth_session; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.root_auth_session (
    id character varying(36) NOT NULL,
    realm_id character varying(36) NOT NULL,
    "timestamp" bigint,
    version integer
);


ALTER TABLE schema_keycloak.root_auth_session OWNER TO postgres;

--
-- Name: scope_mapping; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.scope_mapping (
    client_id character varying(36) NOT NULL,
    role_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.scope_mapping OWNER TO postgres;

--
-- Name: scope_policy; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.scope_policy (
    scope_id character varying(36) NOT NULL,
    policy_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.scope_policy OWNER TO postgres;

--
-- Name: server_config; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.server_config (
    server_config_key character varying(255) NOT NULL,
    value text NOT NULL,
    version integer DEFAULT 0
);


ALTER TABLE schema_keycloak.server_config OWNER TO postgres;

--
-- Name: single_use_object; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.single_use_object (
    id character varying(255) NOT NULL,
    notes text,
    expire bigint NOT NULL
);


ALTER TABLE schema_keycloak.single_use_object OWNER TO postgres;

--
-- Name: user_attribute; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.user_attribute (
    name character varying(255) NOT NULL,
    value character varying(255),
    user_id character varying(36) NOT NULL,
    id character varying(36) DEFAULT 'sybase-needs-something-here'::character varying NOT NULL,
    long_value_hash bytea,
    long_value_hash_lower_case bytea,
    long_value text
);


ALTER TABLE schema_keycloak.user_attribute OWNER TO postgres;

--
-- Name: user_consent; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.user_consent (
    id character varying(36) NOT NULL,
    client_id character varying(255),
    user_id character varying(36) NOT NULL,
    created_date bigint,
    last_updated_date bigint,
    client_storage_provider character varying(36),
    external_client_id character varying(255)
);


ALTER TABLE schema_keycloak.user_consent OWNER TO postgres;

--
-- Name: user_consent_client_scope; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.user_consent_client_scope (
    user_consent_id character varying(36) NOT NULL,
    scope_id character varying(36) NOT NULL,
    parameter character varying(255) DEFAULT '#N A#'::character varying NOT NULL
);


ALTER TABLE schema_keycloak.user_consent_client_scope OWNER TO postgres;

--
-- Name: user_entity; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.user_entity (
    id character varying(36) NOT NULL,
    email character varying(255),
    email_constraint character varying(255),
    email_verified boolean DEFAULT false NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    federation_link character varying(255),
    first_name character varying(255),
    last_name character varying(255),
    realm_id character varying(255),
    username character varying(255),
    created_timestamp bigint,
    service_account_client_link character varying(255),
    not_before integer DEFAULT 0 NOT NULL,
    last_modified_timestamp bigint
);


ALTER TABLE schema_keycloak.user_entity OWNER TO postgres;

--
-- Name: user_federation_config; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.user_federation_config (
    user_federation_provider_id character varying(36) NOT NULL,
    value character varying(255),
    name character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.user_federation_config OWNER TO postgres;

--
-- Name: user_federation_mapper; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.user_federation_mapper (
    id character varying(36) NOT NULL,
    name character varying(255) NOT NULL,
    federation_provider_id character varying(36) NOT NULL,
    federation_mapper_type character varying(255) NOT NULL,
    realm_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.user_federation_mapper OWNER TO postgres;

--
-- Name: user_federation_mapper_config; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.user_federation_mapper_config (
    user_federation_mapper_id character varying(36) NOT NULL,
    value character varying(255),
    name character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.user_federation_mapper_config OWNER TO postgres;

--
-- Name: user_federation_provider; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.user_federation_provider (
    id character varying(36) NOT NULL,
    changed_sync_period integer,
    display_name character varying(255),
    full_sync_period integer,
    last_sync integer,
    priority integer,
    provider_name character varying(255),
    realm_id character varying(36)
);


ALTER TABLE schema_keycloak.user_federation_provider OWNER TO postgres;

--
-- Name: user_group_membership; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.user_group_membership (
    group_id character varying(36) NOT NULL,
    user_id character varying(36) NOT NULL,
    membership_type character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.user_group_membership OWNER TO postgres;

--
-- Name: user_required_action; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.user_required_action (
    user_id character varying(36) NOT NULL,
    required_action character varying(255) DEFAULT ' '::character varying NOT NULL
);


ALTER TABLE schema_keycloak.user_required_action OWNER TO postgres;

--
-- Name: user_role_mapping; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.user_role_mapping (
    role_id character varying(255) NOT NULL,
    user_id character varying(36) NOT NULL
);


ALTER TABLE schema_keycloak.user_role_mapping OWNER TO postgres;

--
-- Name: user_ver_credential; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.user_ver_credential (
    id character varying(36) NOT NULL,
    client_scope_id character varying(36) NOT NULL,
    user_id character varying(36) NOT NULL,
    revision character varying(36) NOT NULL,
    created_date bigint,
    updated_date bigint,
    user_attributes text,
    version integer
);


ALTER TABLE schema_keycloak.user_ver_credential OWNER TO postgres;

--
-- Name: web_origins; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.web_origins (
    client_id character varying(36) NOT NULL,
    value character varying(255) NOT NULL
);


ALTER TABLE schema_keycloak.web_origins OWNER TO postgres;

--
-- Name: workflow_state; Type: TABLE; Schema: schema_keycloak; Owner: postgres
--

CREATE TABLE schema_keycloak.workflow_state (
    execution_id character varying(255) NOT NULL,
    resource_id character varying(255) NOT NULL,
    workflow_id character varying(255) NOT NULL,
    resource_type character varying(255),
    scheduled_step_id character varying(255),
    scheduled_step_timestamp bigint
);


ALTER TABLE schema_keycloak.workflow_state OWNER TO postgres;

--
-- Name: adm_log_audit dlog_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_log_audit ALTER COLUMN dlog_id SET DEFAULT nextval('schema_admin.adm_log_audit_dlog_id_seq'::regclass);


--
-- Name: adm_log_login log_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_log_login ALTER COLUMN log_id SET DEFAULT nextval('schema_admin.adm_log_login_log_id_seq'::regclass);


--
-- Name: adm_mst_application dmap_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_application ALTER COLUMN dmap_id SET DEFAULT nextval('schema_admin.adm_mst_application_dmap_id_seq'::regclass);


--
-- Name: adm_mst_company dmc_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_company ALTER COLUMN dmc_id SET DEFAULT nextval('schema_admin.adm_mst_company_dmc_id_seq'::regclass);


--
-- Name: adm_mst_company_application dmca_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_company_application ALTER COLUMN dmca_id SET DEFAULT nextval('schema_admin.adm_mst_company_application_dmca_id_seq'::regclass);


--
-- Name: adm_mst_company_module dmcm_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_company_module ALTER COLUMN dmcm_id SET DEFAULT nextval('schema_admin.adm_mst_company_module_dmcm_id_seq'::regclass);


--
-- Name: adm_mst_menu_temp dmmt_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_menu_temp ALTER COLUMN dmmt_id SET DEFAULT nextval('schema_admin.adm_mst_menu_temp_dmmt_id_seq'::regclass);


--
-- Name: adm_mst_role_menu dmrm_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_role_menu ALTER COLUMN dmrm_id SET DEFAULT nextval('schema_admin.adm_mst_role_menu_dmrm_id_seq'::regclass);


--
-- Name: adm_mst_role_menu_temp dmrmt_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_role_menu_temp ALTER COLUMN dmrmt_id SET DEFAULT nextval('schema_admin.adm_mst_role_menu_temp_dmrmt_id_seq'::regclass);


--
-- Name: adm_mst_role_temp dmrt_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_role_temp ALTER COLUMN dmrt_id SET DEFAULT nextval('schema_admin.adm_mst_role_temp_dmrt_id_seq'::regclass);


--
-- Name: adm_mst_user_application dmuapp_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_application ALTER COLUMN dmuapp_id SET DEFAULT nextval('schema_admin.adm_mst_user_application_dmuapp_id_seq'::regclass);


--
-- Name: adm_mst_user_application_temp dmuat_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_application_temp ALTER COLUMN dmuat_id SET DEFAULT nextval('schema_admin.adm_mst_user_application_temp_dmuat_id_seq'::regclass);


--
-- Name: adm_mst_user_menu_temp dmumt_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_menu_temp ALTER COLUMN dmumt_id SET DEFAULT nextval('schema_admin.adm_mst_user_menu_temp_dmumt_id_seq'::regclass);


--
-- Name: adm_mst_user_role dmur_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_role ALTER COLUMN dmur_id SET DEFAULT nextval('schema_admin.adm_mst_user_role_dmur_id_seq'::regclass);


--
-- Name: adm_sec_user_pass_recov dsup_id; Type: DEFAULT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_sec_user_pass_recov ALTER COLUMN dsup_id SET DEFAULT nextval('schema_admin.adm_sec_user_pass_recov_dsup_id_seq'::regclass);


--
-- Name: crm_activity activity_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_activity ALTER COLUMN activity_id SET DEFAULT nextval('schema_crm.crm_activity_activity_id_seq'::regclass);


--
-- Name: crm_activity_type activity_type_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_activity_type ALTER COLUMN activity_type_id SET DEFAULT nextval('schema_crm.crm_activity_type_activity_type_id_seq'::regclass);


--
-- Name: crm_competitor competitor_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_competitor ALTER COLUMN competitor_id SET DEFAULT nextval('schema_crm.crm_competitor_competitor_id_seq'::regclass);


--
-- Name: crm_interaction_log log_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_interaction_log ALTER COLUMN log_id SET DEFAULT nextval('schema_crm.crm_interaction_log_log_id_seq'::regclass);


--
-- Name: crm_lead lead_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead ALTER COLUMN lead_id SET DEFAULT nextval('schema_crm.crm_lead_lead_id_seq'::regclass);


--
-- Name: crm_lead_history history_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead_history ALTER COLUMN history_id SET DEFAULT nextval('schema_crm.crm_lead_history_history_id_seq'::regclass);


--
-- Name: crm_lead_source lead_source_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead_source ALTER COLUMN lead_source_id SET DEFAULT nextval('schema_crm.crm_lead_source_lead_source_id_seq'::regclass);


--
-- Name: crm_lost_reason lost_reason_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lost_reason ALTER COLUMN lost_reason_id SET DEFAULT nextval('schema_crm.crm_lost_reason_lost_reason_id_seq'::regclass);


--
-- Name: crm_monthly_target target_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_monthly_target ALTER COLUMN target_id SET DEFAULT nextval('schema_crm.crm_monthly_target_target_id_seq'::regclass);


--
-- Name: crm_stage stage_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_stage ALTER COLUMN stage_id SET DEFAULT nextval('schema_crm.crm_stage_stage_id_seq'::regclass);


--
-- Name: crm_ticket_conversations conversation_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_ticket_conversations ALTER COLUMN conversation_id SET DEFAULT nextval('schema_crm.crm_ticket_conversations_conversation_id_seq'::regclass);


--
-- Name: crm_tickets ticket_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_tickets ALTER COLUMN ticket_id SET DEFAULT nextval('schema_crm.crm_tickets_ticket_id_seq'::regclass);


--
-- Name: hr_employee employee_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.hr_employee ALTER COLUMN employee_id SET DEFAULT nextval('schema_crm.hr_employee_employee_id_seq'::regclass);


--
-- Name: hr_job job_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.hr_job ALTER COLUMN job_id SET DEFAULT nextval('schema_crm.hr_job_job_id_seq'::regclass);


--
-- Name: ir_attachment attachment_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.ir_attachment ALTER COLUMN attachment_id SET DEFAULT nextval('schema_crm.ir_attachment_attachment_id_seq'::regclass);


--
-- Name: mail_message message_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.mail_message ALTER COLUMN message_id SET DEFAULT nextval('schema_crm.mail_message_message_id_seq'::regclass);


--
-- Name: res_currency currency_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_currency ALTER COLUMN currency_id SET DEFAULT nextval('schema_crm.res_currency_currency_id_seq'::regclass);


--
-- Name: res_partner partner_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_partner ALTER COLUMN partner_id SET DEFAULT nextval('schema_crm.res_partner_partner_id_seq'::regclass);


--
-- Name: res_partner_category category_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_partner_category ALTER COLUMN category_id SET DEFAULT nextval('schema_crm.res_partner_category_category_id_seq'::regclass);


--
-- Name: res_partner_contact contact_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_partner_contact ALTER COLUMN contact_id SET DEFAULT nextval('schema_crm.res_partner_contact_contact_id_seq'::regclass);


--
-- Name: res_users user_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_users ALTER COLUMN user_id SET DEFAULT nextval('schema_crm.res_users_user_id_seq'::regclass);


--
-- Name: sales_targets target_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.sales_targets ALTER COLUMN target_id SET DEFAULT nextval('schema_crm.sales_targets_target_id_seq'::regclass);


--
-- Name: sales_team team_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.sales_team ALTER COLUMN team_id SET DEFAULT nextval('schema_crm.sales_team_team_id_seq'::regclass);


--
-- Name: utm_campaign campaign_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.utm_campaign ALTER COLUMN campaign_id SET DEFAULT nextval('schema_crm.utm_campaign_campaign_id_seq'::regclass);


--
-- Name: utm_medium medium_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.utm_medium ALTER COLUMN medium_id SET DEFAULT nextval('schema_crm.utm_medium_medium_id_seq'::regclass);


--
-- Name: utm_source source_id; Type: DEFAULT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.utm_source ALTER COLUMN source_id SET DEFAULT nextval('schema_crm.utm_source_source_id_seq'::regclass);


--
-- Name: hr_log_salary_change dlog_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_log_salary_change ALTER COLUMN dlog_id SET DEFAULT nextval('schema_hrd.hr_log_salary_change_dlog_id_seq'::regclass);


--
-- Name: hr_mst_approval_flow daflow_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_approval_flow ALTER COLUMN daflow_id SET DEFAULT nextval('schema_hrd.hr_mst_approval_flow_daflow_id_seq'::regclass);


--
-- Name: hr_mst_attendance_rule datt_rule_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_attendance_rule ALTER COLUMN datt_rule_id SET DEFAULT nextval('schema_hrd.hr_mst_attendance_rule_datt_rule_id_seq'::regclass);


--
-- Name: hr_mst_bpjs_setting dbpjs_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_bpjs_setting ALTER COLUMN dbpjs_id SET DEFAULT nextval('schema_hrd.hr_mst_bpjs_setting_dbpjs_id_seq'::regclass);


--
-- Name: hr_mst_company_config dcomp_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_company_config ALTER COLUMN dcomp_id SET DEFAULT nextval('schema_hrd.hr_mst_company_config_dcomp_id_seq'::regclass);


--
-- Name: hr_mst_department dmdep_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_department ALTER COLUMN dmdep_id SET DEFAULT nextval('schema_hrd.hr_mst_department_dmdep_id_seq'::regclass);


--
-- Name: hr_mst_employee dmemp_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee ALTER COLUMN dmemp_id SET DEFAULT nextval('schema_hrd.hr_mst_employee_dmemp_id_seq'::regclass);


--
-- Name: hr_mst_employee_payroll_config depc_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee_payroll_config ALTER COLUMN depc_id SET DEFAULT nextval('schema_hrd.hr_mst_employee_payroll_config_depc_id_seq'::regclass);


--
-- Name: hr_mst_employee_tax detax_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee_tax ALTER COLUMN detax_id SET DEFAULT nextval('schema_hrd.hr_mst_employee_tax_detax_id_seq'::regclass);


--
-- Name: hr_mst_formula dform_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_formula ALTER COLUMN dform_id SET DEFAULT nextval('schema_hrd.hr_mst_formula_dform_id_seq'::regclass);


--
-- Name: hr_mst_holiday dmhol_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_holiday ALTER COLUMN dmhol_id SET DEFAULT nextval('schema_hrd.hr_mst_holiday_dmhol_id_seq'::regclass);


--
-- Name: hr_mst_job_grade dgrade_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_job_grade ALTER COLUMN dgrade_id SET DEFAULT nextval('schema_hrd.hr_mst_job_grade_dgrade_id_seq'::regclass);


--
-- Name: hr_mst_leave_type dmlty_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_leave_type ALTER COLUMN dmlty_id SET DEFAULT nextval('schema_hrd.hr_mst_leave_type_dmlty_id_seq'::regclass);


--
-- Name: hr_mst_loan_type dloant_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_loan_type ALTER COLUMN dloant_id SET DEFAULT nextval('schema_hrd.hr_mst_loan_type_dloant_id_seq'::regclass);


--
-- Name: hr_mst_payroll_period dper_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_payroll_period ALTER COLUMN dper_id SET DEFAULT nextval('schema_hrd.hr_mst_payroll_period_dper_id_seq'::regclass);


--
-- Name: hr_mst_payroll_rule drule_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_payroll_rule ALTER COLUMN drule_id SET DEFAULT nextval('schema_hrd.hr_mst_payroll_rule_drule_id_seq'::regclass);


--
-- Name: hr_mst_position dmpos_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_position ALTER COLUMN dmpos_id SET DEFAULT nextval('schema_hrd.hr_mst_position_dmpos_id_seq'::regclass);


--
-- Name: hr_mst_ptkp dptkp_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_ptkp ALTER COLUMN dptkp_id SET DEFAULT nextval('schema_hrd.hr_mst_ptkp_dptkp_id_seq'::regclass);


--
-- Name: hr_mst_salary_component dmsc_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_salary_component ALTER COLUMN dmsc_id SET DEFAULT nextval('schema_hrd.hr_mst_salary_component_dmsc_id_seq'::regclass);


--
-- Name: hr_mst_shift dshift_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_shift ALTER COLUMN dshift_id SET DEFAULT nextval('schema_hrd.hr_mst_shift_dshift_id_seq'::regclass);


--
-- Name: hr_mst_tax_rate dtax_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_tax_rate ALTER COLUMN dtax_id SET DEFAULT nextval('schema_hrd.hr_mst_tax_rate_dtax_id_seq'::regclass);


--
-- Name: hr_txn_approval dapp_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_approval ALTER COLUMN dapp_id SET DEFAULT nextval('schema_hrd.hr_txn_approval_dapp_id_seq'::regclass);


--
-- Name: hr_txn_attendance dmatn_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_attendance ALTER COLUMN dmatn_id SET DEFAULT nextval('schema_hrd.hr_txn_attendance_dmatn_id_seq'::regclass);


--
-- Name: hr_txn_career_history dmcar_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_career_history ALTER COLUMN dmcar_id SET DEFAULT nextval('schema_hrd.hr_txn_career_history_dmcar_id_seq'::regclass);


--
-- Name: hr_txn_contract dmcon_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_contract ALTER COLUMN dmcon_id SET DEFAULT nextval('schema_hrd.hr_txn_contract_dmcon_id_seq'::regclass);


--
-- Name: hr_txn_document dmdoc_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_document ALTER COLUMN dmdoc_id SET DEFAULT nextval('schema_hrd.hr_txn_document_dmdoc_id_seq'::regclass);


--
-- Name: hr_txn_employee_payroll_rule depr_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_payroll_rule ALTER COLUMN depr_id SET DEFAULT nextval('schema_hrd.hr_txn_employee_payroll_rule_depr_id_seq'::regclass);


--
-- Name: hr_txn_employee_salary dmsal_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_salary ALTER COLUMN dmsal_id SET DEFAULT nextval('schema_hrd.hr_txn_employee_salary_dmsal_id_seq'::regclass);


--
-- Name: hr_txn_employee_salary_detail dmsald_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_salary_detail ALTER COLUMN dmsald_id SET DEFAULT nextval('schema_hrd.hr_txn_employee_salary_detail_dmsald_id_seq'::regclass);


--
-- Name: hr_txn_employee_shift deshift_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_shift ALTER COLUMN deshift_id SET DEFAULT nextval('schema_hrd.hr_txn_employee_shift_deshift_id_seq'::regclass);


--
-- Name: hr_txn_leave_balance dmlbal_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_leave_balance ALTER COLUMN dmlbal_id SET DEFAULT nextval('schema_hrd.hr_txn_leave_balance_dmlbal_id_seq'::regclass);


--
-- Name: hr_txn_leave_request dmlreq_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_leave_request ALTER COLUMN dmlreq_id SET DEFAULT nextval('schema_hrd.hr_txn_leave_request_dmlreq_id_seq'::regclass);


--
-- Name: hr_txn_loan dmlon_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_loan ALTER COLUMN dmlon_id SET DEFAULT nextval('schema_hrd.hr_txn_loan_dmlon_id_seq'::regclass);


--
-- Name: hr_txn_overtime dmovt_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_overtime ALTER COLUMN dmovt_id SET DEFAULT nextval('schema_hrd.hr_txn_overtime_dmovt_id_seq'::regclass);


--
-- Name: hr_txn_payslip dmps_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_payslip ALTER COLUMN dmps_id SET DEFAULT nextval('schema_hrd.hr_txn_payslip_dmps_id_seq'::regclass);


--
-- Name: hr_txn_payslip_line dmpsl_id; Type: DEFAULT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_payslip_line ALTER COLUMN dmpsl_id SET DEFAULT nextval('schema_hrd.hr_txn_payslip_line_dmpsl_id_seq'::regclass);


--
-- Data for Name: crm_lead_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.crm_lead_history (history_id, changed_at, description, lead_id, new_stage_id, old_stage_id) FROM stdin;
\.


--
-- Data for Name: crm_lead_source; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.crm_lead_source (lead_source_id, name) FROM stdin;
\.


--
-- Data for Name: adm_log_audit; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_log_audit (dlog_id, dlog_action, dlog_table_name, dlog_record_id, dlog_old_data, dlog_new_data, dlog_ip_address, dlog_user_agent, dlog_created_datetime, dlog_created_by) FROM stdin;
\.


--
-- Data for Name: adm_log_login; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_log_login (log_id, user_id, username, login_datetime, ip_address, user_agent, device_id, login_status, company_id, remarks) FROM stdin;
1	8	budi.santoso	2026-10-26 16:08:46.110036	0:0:0:0:0:0:0:1	PostmanRuntime/7.53.0	test-device-001	SUCCESS	1	\N
\.


--
-- Data for Name: adm_mst_application; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_application (dmap_id, dmap_application_code, dmap_application_name, dmap_description, dmap_is_active, dmap_created_datetime, dmap_created_by, dmap_modified_datetime, dmap_modified_by) FROM stdin;
1	ACC	Accounting System	Modul Akuntansi Standar (GL, AP, AR, Inventory, dll)	t	2026-10-23 13:42:48.590114	system	\N	\N
2	CRM	CRM System	Customer Relationship Management	t	2026-10-23 13:42:48.590114	system	\N	\N
3	HRD	HRD System	Human Resource & Payroll	t	2026-10-23 13:42:48.590114	system	\N	\N
\.


--
-- Data for Name: adm_mst_branch; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_branch (dmbra_id, dmbra_regional_id, dmbra_branch_code, dmbra_branch_name, dmbra_is_active, dmbra_created_datetime, dmbra_created_by, dmbra_modified_datetime, dmbra_modified_by) FROM stdin;
\.


--
-- Data for Name: adm_mst_company; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_company (dmc_id, dmc_company_code, dmc_company_name, dmc_is_active, dmc_platform_code, dmc_platform_name, dmc_address, dmc_created_datetime, dmc_created_by, dmc_modified_datetime, dmc_modified_by) FROM stdin;
1	COMP01	PT Maju Jaya	1.00	\N	\N	\N	2026-10-23 13:42:02.090858	system	\N	\N
2	COMP02	CV Sukses Bersama	1.00	\N	\N	\N	2026-10-23 13:42:02.090858	system	\N	\N
3	COMP03	PT Global Tech	1.00	\N	\N	\N	2026-10-23 13:42:02.090858	system	\N	\N
\.


--
-- Data for Name: adm_mst_company_application; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_company_application (dmca_id, dmca_company_id, dmca_application_id, dmca_is_active, dmca_activated_date, dmca_expired_date, dmca_created_datetime, dmca_created_by, dmca_modified_datetime, dmca_modified_by) FROM stdin;
7	1	1	t	2026-10-23 13:45:15.341177	\N	2026-10-23 13:45:15.341177	system	\N	\N
8	1	2	t	2026-10-23 13:45:15.341177	\N	2026-10-23 13:45:15.341177	system	\N	\N
9	2	1	t	2026-10-23 13:45:15.341177	\N	2026-10-23 13:45:15.341177	system	\N	\N
10	3	3	t	2026-10-23 13:45:15.341177	\N	2026-10-23 13:45:15.341177	system	\N	\N
\.


--
-- Data for Name: adm_mst_company_module; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_company_module (dmcm_id, dmcm_company_id, dmcm_module_id, dmcm_is_active, dmcm_created_datetime, dmcm_created_by, dmcm_modified_datetime, dmcm_modified_by) FROM stdin;
\.


--
-- Data for Name: adm_mst_currency; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_currency (dmcur_id, dmcur_company_id, dmcur_currency_code, dmcur_currency_name, dmcur_is_active, dmcur_created_datetime, dmcur_created_by, dmcur_modified_datetime, dmcur_modified_by) FROM stdin;
\.


--
-- Data for Name: adm_mst_menu; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_menu (dmmenu_id, dmmenu_parent_menu_id, dmmenu_code, dmmenu_menu_name, dmmenu_menu_link, dmmenu_menu_index, dmmenu_is_active, dmmenu_icon_name, dmmenu_created_datetime, dmmenu_created_by, dmmenu_modified_datetime, dmmenu_modified_by, dmmenu_company_code, dmmenu_currency_code, dmmenu_module_id, dmmenu_show_in_sidemenu) FROM stdin;
1001	\N	ACC-GL	General Ledger	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	101	\N
1003	1001	ACC-GL-JOURNAL	Journal Entry	/acc/gl/journal	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	101	\N
1004	1001	ACC-GL-LEDGER	General Ledger	/acc/gl/ledger	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	101	\N
1010	\N	ACC-AP	Account Payable	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	102	\N
1011	1010	ACC-AP-VENDOR	Vendor	/acc/ap/vendor	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	102	\N
1012	1010	ACC-AP-INVOICE	AP Invoice	/acc/ap/invoice	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	102	\N
1013	1010	ACC-AP-PAYMENT	AP Payment	/acc/ap/payment	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	102	\N
1020	\N	ACC-AR	Account Receivable	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	103	\N
1021	1020	ACC-AR-CUSTOMER	Customer	/acc/ar/customer	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	103	\N
1022	1020	ACC-AR-INVOICE	AR Invoice	/acc/ar/invoice	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	103	\N
1023	1020	ACC-AR-RECEIPT	AR Receipt	/acc/ar/receipt	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	103	\N
1030	\N	ACC-INV	Inventory	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	104	\N
1031	1030	ACC-INV-ITEM	Item	/acc/inv/item	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	104	\N
1032	1030	ACC-INV-STOCK	Stock Balance	/acc/inv/stock	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	104	\N
1033	1030	ACC-INV-TRANSFER	Stock Transfer	/acc/inv/transfer	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	104	\N
1040	\N	ACC-CB	Cash & Bank	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	105	\N
1041	1040	ACC-CB-CASH	Cash Bank	/acc/cb/cashbank	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	105	\N
1042	1040	ACC-CB-RECON	Bank Reconciliation	/acc/cb/reconciliation	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	105	\N
1050	\N	ACC-FA	Fixed Asset	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	106	\N
1051	1050	ACC-FA-ASSET	Asset Master	/acc/fa/asset	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	106	\N
1052	1050	ACC-FA-DEPR	Depreciation	/acc/fa/depreciation	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	106	\N
1060	\N	ACC-TAX	Taxation	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	107	\N
1061	1060	ACC-TAX-VAT	VAT	/acc/tax/vat	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	107	\N
1062	1060	ACC-TAX-WHT	Withholding Tax	/acc/tax/wht	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	107	\N
1070	\N	ACC-RPT	Reporting	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	108	\N
1071	1070	ACC-RPT-TB	Trial Balance	/acc/report/trial-balance	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	108	\N
1072	1070	ACC-RPT-PL	Profit & Loss	/acc/report/profit-loss	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	108	\N
1073	1070	ACC-RPT-BS	Balance Sheet	/acc/report/balance-sheet	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	108	\N
2001	\N	CRM-LEAD	Lead Management	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	201	\N
2002	2001	CRM-LEAD-LIST	Lead	/crm/lead	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	201	\N
2010	\N	CRM-CONTACT	Contact Management	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	202	\N
2011	2010	CRM-CONTACT-LIST	Contact	/crm/contact	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	202	\N
2020	\N	CRM-OPP	Opportunity	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	203	\N
2021	2020	CRM-OPP-LIST	Opportunity	/crm/opportunity	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	203	\N
2030	\N	CRM-ACT	Activity	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	204	\N
2031	2030	CRM-ACT-LIST	Activity	/crm/activity	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	204	\N
2040	\N	CRM-QUO	Quotation	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	205	\N
2041	2040	CRM-QUO-LIST	Quotation	/crm/quotation	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	205	\N
2050	\N	CRM-RPT	Reporting CRM	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	206	\N
2051	2050	CRM-RPT-DASH	CRM Dashboard	/crm/report/dashboard	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	206	\N
3001	\N	HRD-EMP	Employee	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	301	\N
3002	3001	HRD-EMP-LIST	Employee Master	/hrd/employee	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	301	\N
3010	\N	HRD-ATT	Attendance	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	302	\N
3011	3010	HRD-ATT-LIST	Attendance	/hrd/attendance	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	302	\N
3020	\N	HRD-LEAVE	Leave Management	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	303	\N
3021	3020	HRD-LEAVE-LIST	Leave Request	/hrd/leave	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	303	\N
3030	\N	HRD-PAY	Payroll	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	304	\N
3031	3030	HRD-PAY-LIST	Payroll Process	/hrd/payroll	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	304	\N
3040	\N	HRD-ORG	Organization	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	305	\N
3041	3040	HRD-ORG-DEPT	Department	/hrd/organization/department	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	305	\N
3042	3040	HRD-ORG-POS	Position	/hrd/organization/position	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	305	\N
3050	\N	HRD-RPT	Reporting HR	\N	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	306	\N
3051	3050	HRD-RPT-DASH	HR Dashboard	/hrd/report/dashboard	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	306	\N
1002	1001	ACC-GL-COA	Chart of Account	/acc/gl/coa	\N	1	\N	2026-10-23 13:44:50.688304	system	\N	\N	\N	\N	101	\N
\.


--
-- Data for Name: adm_mst_menu_temp; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_menu_temp (dmmt_id, dmmt_menu_id, dmmt_parent_menu_id, dmmt_code, dmmt_menu_name, dmmt_menu_link, dmmt_menu_index, dmmt_is_active, dmmt_icon_name, dmmt_created_datetime, dmmt_created_by, dmmt_modified_datetime, dmmt_modified_by, dmmt_company_code, dmmt_currency_code, dmmt_status, dmmt_revise_reason, dmmt_module_id, dmmt_show_in_sidemenu) FROM stdin;
\.


--
-- Data for Name: adm_mst_regional; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_regional (dmreg_id, dmreg_company_id, dmreg_regional_code, dmreg_regional_name, dmreg_is_active, dmreg_created_datetime, dmreg_created_by, dmreg_modified_datetime, dmreg_modified_by) FROM stdin;
\.


--
-- Data for Name: adm_mst_role; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_role (dmrole_id, dmrole_role_name, dmrole_is_active, dmrole_created_datetime, dmrole_created_by, dmrole_modified_datetime, dmrole_modified_by, dmrole_company_code, dmrole_currency_code, dmrole_application_id, dmrole_company_id) FROM stdin;
2	Accounting Admin	1	2026-10-23 13:45:36.464859	system	\N	\N	\N	\N	\N	1
3	CRM User	1	2026-10-23 13:45:36.464859	system	\N	\N	\N	\N	\N	1
4	HR Admin	1	2026-10-23 13:45:36.464859	system	\N	\N	\N	\N	\N	3
1	Super Admin	1	2026-10-23 13:45:36.464859	system	\N	\N	\N	\N	\N	\N
\.


--
-- Data for Name: adm_mst_role_menu; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_role_menu (dmrm_id, dmrm_role_id, dmrm_menu_id, dmrm_is_view, dmrm_is_add, dmrm_is_edit, dmrm_is_delete, dmrm_is_approve, dmrm_is_active, dmrm_created_datetime, dmrm_created_by, dmrm_modified_datetime, dmrm_modified_by) FROM stdin;
1	1	1002	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
2	1	1003	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
3	1	1004	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
4	1	1011	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
5	1	1012	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
6	1	1013	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
7	1	1021	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
8	1	1022	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
9	1	1023	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
10	1	1031	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
11	1	1032	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
12	1	1033	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
13	1	1041	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
14	1	1042	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
15	1	1051	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
16	1	1052	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
17	1	1061	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
18	1	1062	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
19	1	1071	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
20	1	1072	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
21	1	1073	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
22	1	2002	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
23	1	2011	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
24	1	2021	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
25	1	2031	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
26	1	2041	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
27	1	2051	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
28	1	3002	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
29	1	3011	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
30	1	3021	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
32	1	3041	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
33	1	3042	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
34	1	3051	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
35	2	1002	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
36	2	1003	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
37	2	1004	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
38	2	1011	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
39	2	1012	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
40	2	1013	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
41	2	1021	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
42	2	1022	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
43	2	1023	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
44	2	1031	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
45	2	1032	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
46	2	1033	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
47	2	1041	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
48	2	1042	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
49	2	1051	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
50	2	1052	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
51	2	1061	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
52	2	1062	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
53	2	1071	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
54	2	1072	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
55	2	1073	1	1	1	0	0	\N	2026-10-23 13:48:45.831269	system	\N	\N
31	4	3030	1	1	1	1	1	\N	2026-10-23 13:48:42.317791	system	\N	\N
56	4	3002	1	1	1	0	0	\N	2026-10-26 15:07:38.241316	system	\N	\N
57	4	3011	1	1	1	0	0	\N	2026-10-26 15:07:38.241316	system	\N	\N
58	4	3021	1	1	1	0	0	\N	2026-10-26 15:07:38.241316	system	\N	\N
59	4	3031	1	1	1	0	0	\N	2026-10-26 15:07:38.241316	system	\N	\N
60	4	3041	1	1	1	0	0	\N	2026-10-26 15:07:38.241316	system	\N	\N
61	4	3042	1	1	1	0	0	\N	2026-10-26 15:07:38.241316	system	\N	\N
62	4	3051	1	1	1	0	0	\N	2026-10-26 15:07:38.241316	system	\N	\N
\.


--
-- Data for Name: adm_mst_role_menu_temp; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_role_menu_temp (dmrmt_id, dmrmt_role_menu_id, dmrmt_role_id, dmrmt_menu_id, dmrmt_is_view, dmrmt_is_add, dmrmt_is_edit, dmrmt_is_delete, dmrmt_is_approve, dmrmt_is_active, dmrmt_created_datetime, dmrmt_created_by, dmrmt_modified_datetime, dmrmt_modified_by, dmrmt_status, dmrmt_revise_reason, dmrmt_company_code, dmrmt_currency_code) FROM stdin;
\.


--
-- Data for Name: adm_mst_role_temp; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_role_temp (dmrt_id, dmrt_role_id, dmrt_role_name, dmrt_is_active, dmrt_created_datetime, dmrt_created_by, dmrt_modified_datetime, dmrt_modified_by, dmrt_status, dmrt_revise_reason, dmrt_company_code, dmrt_currency_code) FROM stdin;
\.


--
-- Data for Name: adm_mst_sub_branch; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_sub_branch (dmsbr_id, dmsbr_branch_id, dmsbr_sub_branch_code, dmsbr_sub_branch_name, dmsbr_is_active, dmsbr_created_datetime, dmsbr_created_by, dmsbr_modified_datetime, dmsbr_modified_by) FROM stdin;
\.


--
-- Data for Name: adm_mst_user_application; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_user_application (dmuapp_id, dmuapp_role_id, dmuapp_employee_code, dmuapp_name, dmuapp_username, dmuapp_email, dmuapp_mobilephone, dmuapp_is_active, dmuapp_is_login, dmuapp_login_date, dmuapp_created_datetime, dmuapp_created_by, dmuapp_modified_datetime, dmuapp_modified_by, dmuapp_logout_date, dmuapp_company, dmuapp_currency, dmuapp_regional, dmuapp_branch, dmuapp_subbranch, dmuapp_password, dmuapp_last_change_pwd, dmuapp_must_change_pwd, dmuapp_application_id, dmuapp_company_id) FROM stdin;
8	1	1	Budi Santoso	budi.santoso	budi.santoso@contoh.com	\N	1	\N	\N	2026-10-23 13:55:08.068109	system	\N	\N	\N	COMP01	\N	\N	\N	\N	\N	\N	\N	\N	1
9	2	2	Siti Akuntansi	siti.acc	siti.acc@contoh.com	\N	1	\N	\N	2026-10-23 13:55:08.068109	system	\N	\N	\N	COMP01	\N	\N	\N	\N	\N	\N	\N	\N	1
10	3	3	Andi CRM	andi.crm	andi.crm@contoh.com	\N	1	\N	\N	2026-10-23 13:55:08.068109	system	\N	\N	\N	COMP01	\N	\N	\N	\N	\N	\N	\N	\N	1
11	4	4	Dewi HR	dewi.hr	dewi.hr@contoh.com	\N	1	\N	\N	2026-10-23 13:55:08.068109	system	\N	\N	\N	COMP03	\N	\N	\N	\N	\N	\N	\N	\N	3
\.


--
-- Data for Name: adm_mst_user_application_temp; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_user_application_temp (dmuat_id, dmuat_user_id, dmuat_role_id, dmuat_name, dmuat_username, dmuat_email, dmuat_mobilephone, dmuat_is_active, dmuat_is_login, dmuat_login_date, dmuat_logout_date, dmuat_status, dmuat_revise_reason, dmuat_created_datetime, dmuat_created_by, dmuat_modified_datetime, dmuat_modified_by, dmuat_company, dmuat_currency, dmuat_regional, dmuat_branch, dmuat_subbranch) FROM stdin;
\.


--
-- Data for Name: adm_mst_user_menu; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_user_menu (dmum_id, dmum_user_id, dmum_menu_id, dmum_is_view, dmum_is_add, dmum_is_edit, dmum_is_delete, dmum_is_approve, dmum_valid_from, dmum_valid_to, dmum_created_datetime, dmum_created_by, dmum_modified_datetime, dmum_modified_by, dmum_company_code, dmum_currency_code, dmrm_id, dmrm_role_id, dmrm_menu_id, dmrm_is_view, dmrm_is_add, dmrm_is_edit, dmrm_is_delete, dmrm_is_approve, dmrm_is_active, dmrm_created_datetime, dmrm_created_by, dmrm_modified_datetime, dmrm_modified_by) FROM stdin;
\.


--
-- Data for Name: adm_mst_user_menu_temp; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_user_menu_temp (dmumt_id, dmumt_user_menu_id, dmumt_user_id, dmumt_menu_id, dmumt_is_view, dmumt_is_add, dmumt_is_edit, dmumt_is_delete, dmumt_is_approve, dmumt_is_active, dmumt_created_datetime, dmumt_created_by, dmumt_modified_datetime, dmumt_modified_by, dmumt_company_code, dmumt_currency_code, dmumt_status, dmumt_revise_reason, dmumt_valid_from, dmumt_valid_to) FROM stdin;
\.


--
-- Data for Name: adm_mst_user_role; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_mst_user_role (dmur_id, dmur_user_id, dmur_role_id, dmur_is_active, dmur_created_datetime, dmur_created_by, dmur_modified_datetime, dmur_modified_by) FROM stdin;
\.


--
-- Data for Name: adm_sec_modules; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_sec_modules (dsmd_module_id, dsmd_module_name, dsmd_app_path_url, dsmd_desc, dsmd_status, dsmd_created_by, dsmd_created_date, dsmd_updated_by, dsmd_updated_date, dsmd_application_id) FROM stdin;
101	General Ledger	\N	\N	A	system	\N	\N	\N	1
102	Account Payable	\N	\N	A	system	\N	\N	\N	1
103	Account Receivable	\N	\N	A	system	\N	\N	\N	1
104	Inventory	\N	\N	A	system	\N	\N	\N	1
105	Cash & Bank	\N	\N	A	system	\N	\N	\N	1
106	Fixed Asset	\N	\N	A	system	\N	\N	\N	1
107	Taxation	\N	\N	A	system	\N	\N	\N	1
108	Reporting	\N	\N	A	system	\N	\N	\N	1
201	Lead Management	\N	\N	A	system	\N	\N	\N	2
202	Contact Management	\N	\N	A	system	\N	\N	\N	2
203	Opportunity	\N	\N	A	system	\N	\N	\N	2
204	Activity	\N	\N	A	system	\N	\N	\N	2
205	Quotation	\N	\N	A	system	\N	\N	\N	2
206	Reporting CRM	\N	\N	A	system	\N	\N	\N	2
301	Employee	\N	\N	A	system	\N	\N	\N	3
302	Attendance	\N	\N	A	system	\N	\N	\N	3
303	Leave Management	\N	\N	A	system	\N	\N	\N	3
304	Payroll	\N	\N	A	system	\N	\N	\N	3
305	Organization	\N	\N	A	system	\N	\N	\N	3
306	Reporting HR	\N	\N	A	system	\N	\N	\N	3
\.


--
-- Data for Name: adm_sec_user_pass_recov; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.adm_sec_user_pass_recov (dsup_id, dsup_user_id, dsup_user_name, dsup_token, dsup_exp, dsup_used, dsup_created_date) FROM stdin;
\.


--
-- Data for Name: dge_mst_menu_inherit; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.dge_mst_menu_inherit (dmmi_menu_parent_id, dmmi_menu_child_id) FROM stdin;
\.


--
-- Data for Name: dge_mst_user_application_device; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.dge_mst_user_application_device (dmuad_device_id, dmuad_user_id, dmuad_created_datetime, dmuad_valid_date) FROM stdin;
\.


--
-- Data for Name: utl_sys_config; Type: TABLE DATA; Schema: schema_admin; Owner: postgres
--

COPY schema_admin.utl_sys_config (usc_appl, usc_key, usc_data, usc_created_date, usc_created_by, usc_updated_date, usc_updated_by) FROM stdin;
\.


--
-- Data for Name: crm_activity; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.crm_activity (activity_id, lead_id, activity_type_id, summary, note, date_deadline, user_id, is_done, done_date, created_at, end_time, start_time, contact_phone) FROM stdin;
3	4	5	yyyyy	\N	2026-03-27	1	t	2026-03-27 16:16:55.894649	2026-03-27 15:58:44.641582	\N	\N	\N
4	4	5	tet	\N	2026-03-27	1	t	2026-03-27 16:23:00.349406	2026-03-27 16:22:48.611865	\N	\N	\N
6	5	7	yytyyy	\N	2026-03-26	1	f	\N	2026-03-30 09:17:09.966661	13:21:00	13:21:00	\N
5	4	5	tet	\N	2026-03-27	1	t	2026-03-31 13:39:56.551836	2026-03-27 16:23:25.940002	\N	\N	\N
7	6	8	yuyty	\N	2026-04-02	1	t	2026-03-31 14:33:31.503379	2026-03-30 09:43:10.947058	\N	\N	\N
8	12	5	telepon client	\N	2026-04-02	1	t	2026-03-31 16:04:58.279416	2026-03-31 14:32:12.959628	15:33:00	14:33:00	\N
9	12	5	meeting	Otomatis selesai via Interaction Log	2026-03-31	1	t	\N	2026-03-31 16:15:29.181034	\N	\N	\N
12	12	5	wwww	Otomatis selesai via Interaction Log	2026-04-01	1	t	\N	2026-03-31 16:49:46.104984	\N	\N	\N
14	12	9	test refresh calender 1	\N	2026-04-29	1	f	\N	2026-04-01 11:45:39.133277	\N	\N	\N
10	12	10	meeting online dong	Otomatis selesai via Interaction Log	2026-04-10	2	t	\N	2026-03-31 16:33:25.495341	\N	09:38:00	\N
11	12	5	Cek Progress via Telpon	Otomatis selesai via Interaction Log	2026-03-31	2	t	\N	2026-03-31 16:43:23.048852	\N	\N	\N
13	12	10	test calender	\N	2026-04-23	2	f	\N	2026-04-01 11:27:49.723075	15:31:00	14:30:00	\N
15	12	7	test integration cal	\N	2026-04-01	1	f	\N	2026-04-01 15:27:57.921157	17:29:00	16:28:00	\N
16	12	7	lembur	\N	2026-05-09	1	f	\N	2026-04-01 15:32:36.52787	20:37:00	19:36:00	\N
\.


--
-- Data for Name: crm_activity_type; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.crm_activity_type (activity_type_id, name, icon, is_active) FROM stdin;
5	Telepon	fa-phone	t
6	Meeting (Offline)	fa-handshake	t
7	Meeting (Online)	fa-video	t
8	Email	fa-envelope	t
9	WhatsApp/Chat	fa-brands fa-whatsapp	t
10	Follow Up Proposal	fa-file-signature	t
\.


--
-- Data for Name: crm_competitor; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.crm_competitor (competitor_id, name, strength, weakness, is_active, website, created_at) FROM stdin;
\.


--
-- Data for Name: crm_interaction_log; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.crm_interaction_log (log_id, lead_id, user_id, interaction_type, note, interaction_date, activity_id, attachment_data, attachment_name) FROM stdin;
5	12	1	WhatsApp	Kirim pesan WhatsApp tanya progres	2026-03-31 12:51:19.322477	\N	\N	\N
6	12	1	Call	ccccccccccc	2026-03-31 12:51:20.807722	\N	\N	\N
7	12	1	Call	Telepon customer untuk follow up penawaran	2026-03-31 13:29:55.678161	\N	\N	\N
8	12	1	Call	teststsssssss	2026-03-31 13:30:13.871193	\N	\N	\N
9	12	1	Call	yyiyuyiuyi	2026-03-31 13:30:30.29627	\N	\N	\N
10	12	1	Call	gghjgjhghjghjghj	2026-03-31 13:31:08.995419	\N	\N	\N
11	12	1	WhatsApp	test dari aktifitas saya.........	2026-03-31 16:04:36.172537	\N	\N	\N
12	12	1	Call	Sudah ditelepon untuk follow up	2026-03-31 16:09:28.652243	\N	\N	\N
13	12	1	Call	Sudah ditelepon untuk follow up	2026-03-31 16:19:38.724223	\N	\N	\N
14	12	1	WhatsApp	"Sudah tanya kabar via WA, prospek tertarik lanjut	2026-03-31 16:22:53.938475	\N	\N	\N
15	12	1	WhatsApp	tetw	2026-03-31 16:27:36.831963	\N	\N	\N
16	12	1	WhatsApp	test 123123123	2026-03-31 16:32:44.513414	\N	\N	\N
17	12	1	Call	Sudah ditelepon untuk follow up	2026-03-31 16:35:12.556403	\N	\N	\N
18	6	1	Call	Sudah ditelepon untuk follow up	2026-03-31 16:37:32.234493	\N	\N	\N
19	12	1	Call	Sudah ditelepon untuk follow up	2026-03-31 16:44:33.866081	\N	\N	\N
20	12	1	Call	asdfsadfasfd	2026-03-31 16:47:52.662749	\N	\N	\N
21	12	1	Call	Sudah ditelepon, hasilnya: test 1231231	2026-03-31 16:57:11.23725	\N	\N	\N
1	4	1	Meeting	Meeting / Kunjungan ke lokasi customer	2026-03-31 12:48:16.250249	\N	\N	aaa
2	4	1	Call	teting meet online	2026-03-31 12:48:19.752552	\N	\N	bbb
3	12	1	Meeting	Meeting / Kunjungan ke lokasi customer	2026-03-31 12:49:02.430281	\N	\N	cc
4	12	1	Call	test meeting	2026-03-31 12:49:07.908208	\N	\N	ddd
\.


--
-- Data for Name: crm_lead; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.crm_lead (lead_id, type, name, partner_id, contact_name, email_from, phone, stage_id, sales_team_id, currency_id, expected_revenue, probability, campaign_id, source_id, medium_id, date_deadline, date_closed, lost_reason_id, description, is_active, created_by, created_at, updated_at, priority, contact_phone, user_id, lead_source_id, partner_contact_id) FROM stdin;
5	lead	PT. ABC123	\N	Lily	\N	\N	1	\N	\N	10000000.00	10.00	\N	\N	\N	\N	\N	\N	\N	t	\N	2026-03-27 14:27:22.183895	2026-03-27 14:27:22.183895	0	\N	\N	\N	\N
4	lead	Maintenance Support Tahunan	3	\N	\N	\N	1	2	\N	15000000.00	90.00	\N	\N	\N	\N	\N	\N	Hubungan personal dengan owner sangat baik	t	\N	2026-03-27 09:32:53.675674	2026-03-27 09:32:53.675674	3	123	\N	\N	\N
1	opportunity	Pengadaan Server & ERP Tahap 1	1	Andi Susanto	\N	\N	1	1	\N	850000000.00	100.00	2	\N	\N	\N	\N	\N	Client butuh implementasi cepat sebelum tutup anggaran tahun ini.	t	\N	2026-03-27 09:27:07.511985	2026-03-27 13:39:41.61105	3	123	\N	\N	\N
3	lead	Sistem HRIS Terintegrasi	3	\N	\N	\N	2	1	\N	1200000000.00	20.00	\N	\N	\N	2026-06-30	\N	\N	\N	t	\N	2026-03-27 09:31:38.766954	2026-03-27 14:59:39.680296	1	321	\N	\N	\N
6	lead	uyiui	4	uyyy	\N	\N	2	2	\N	10000000.00	10.00	1	\N	\N	\N	\N	\N	tests 123	t	\N	2026-03-30 09:41:16.287226	2026-04-02 09:20:15.609039	3	231	\N	\N	\N
13	lead	hjghjghjg	\N	\N	\N	\N	1	\N	\N	1255555555.00	10.00	\N	\N	\N	2026-04-29	\N	\N	\N	t	\N	2026-04-02 09:52:09.865956	2026-04-02 09:52:09.865956	0	\N	1	\N	\N
14	lead	test123 propek baru	3	\N	\N	\N	1	2	\N	129999999.00	10.00	\N	\N	\N	2026-04-02	\N	\N	\N	t	\N	2026-04-02 09:57:29.683644	2026-04-02 09:57:29.683644	0	\N	2	\N	\N
15	lead	prosepek baru button batal	1	\N	\N	\N	1	1	\N	12000000.00	10.00	1	\N	\N	2026-04-30	\N	\N	\N	t	\N	2026-04-02 10:16:37.306563	2026-04-02 10:16:37.306563	0	\N	2	\N	\N
17	lead	prosepasdf asdfasdfasdfasf	\N	\N	\N	\N	\N	\N	\N	0.00	10.00	2	\N	\N	2026-04-02	\N	\N	fdfdgfdgfdgdtyrut65765765765	t	\N	2026-04-02 10:35:39.783407	2026-04-02 11:49:09.43069	0	0811111111	1	3	\N
2	opportunity	Layanan SEO & Ads 6 Bulan	4	\N	\N	\N	5	3	\N	45000000.00	100.00	5	\N	\N	\N	\N	\N	Tanya-tanya paket bundling dengan manajemen Instagram	t	\N	2026-03-27 09:28:50.403612	2026-04-02 15:12:38.570328	2	132	\N	\N	\N
12	lead	yuuyuytest lead	4	yuyuy	lili@gmail.com	\N	\N	4	\N	76786878.00	10.00	1	\N	\N	2026-04-11	\N	\N	test leads	t	\N	2026-03-30 11:30:26.896941	2026-04-02 16:00:39.063856	2	0816343434	2	2	\N
\.


--
-- Data for Name: crm_lead_history; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.crm_lead_history (history_id, lead_id, old_stage_id, new_stage_id, description, changed_at) FROM stdin;
1	2	1	2	quo	2026-03-27 14:08:06.72877
2	2	2	3	pro	2026-03-27 14:09:02.63478
3	2	3	2	proposal salah....	2026-03-27 14:09:31.916331
4	3	1	2	test	2026-03-27 14:59:39.676407
5	2	2	3	pingdah ke proposal	2026-04-02 09:19:44.777706
6	6	1	2	pindah ah	2026-04-02 09:20:15.604534
7	2	3	4	nego	2026-04-02 15:12:30.283281
8	2	4	5	menang.....	2026-04-02 15:12:38.567334
\.


--
-- Data for Name: crm_lead_source; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.crm_lead_source (lead_source_id, name) FROM stdin;
1	Website / Pencarian Organik
2	Google Ads
3	Instagram / Facebook Ads
4	Referensi Teman / Klien Lama
5	Pameran / Event Offline
\.


--
-- Data for Name: crm_lost_reason; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.crm_lost_reason (lost_reason_id, name, is_active, description, created_at) FROM stdin;
1	Harga Terlalu Tinggi	t	Klien merasa penawaran melebihi anggaran yang mereka miliki atau mereka sengaja mencari opsi yang lebih murah	2026-03-26 11:09:51.522957
2	Kalah dari Kompetitor	t	Klien memutuskan untuk menggunakan produk, jasa, atau layanan dari perusahaan pesaing (bisa ditambahkan catatan nama pesaingnya nanti di detail prospek)	2026-03-26 11:10:20.19261
3	Proyek Dibatalkan / Pending	t	Klien membatalkan niat pembelian karena ada perubahan manajemen internal, pemotongan anggaran, atau perubahan prioritas bisnis mereka	2026-03-26 11:10:48.838691
4	Fitur/Layanan Tidak Sesuai	t	Kebutuhan spesifik klien ternyata tidak dapat dipenuhi oleh produk atau batasan layanan kita saat ini	2026-03-26 11:11:12.64798
5	Klien Menghilang (Ghosting)	t	Klien sama sekali berhenti membalas pesan, email, atau telepon setelah tahap kualifikasi atau setelah penawaran dikirimkan.	2026-03-26 11:11:48.775322
\.


--
-- Data for Name: crm_monthly_target; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.crm_monthly_target (target_id, user_id, target_month, target_year, target_amount, created_at) FROM stdin;
\.


--
-- Data for Name: crm_stage; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.crm_stage (stage_id, name, sequence, is_won, is_active) FROM stdin;
1	New	\N	f	t
2	Qualified	\N	f	t
3	Proposal	\N	f	t
4	Negotiation	\N	f	t
5	Won	\N	t	t
9	Lost	\N	f	t
\.


--
-- Data for Name: crm_ticket_conversations; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.crm_ticket_conversations (conversation_id, ticket_id, user_id, message, attachment_name, attachment_data, created_at) FROM stdin;
1	1	1	masla status anda open  	\N	\N	2026-04-03 11:10:14.868027
\.


--
-- Data for Name: crm_tickets; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.crm_tickets (ticket_id, ticket_number, subject, description, status, priority, partner_id, assigned_to, created_at, updated_at) FROM stdin;
1	TKT-20260403-110458	maslah 111111	test 123123	OPEN	MEDIUM	1	\N	2026-04-03 11:04:58.715753	2026-04-03 11:05:34.485348
\.


--
-- Data for Name: hr_employee; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.hr_employee (employee_id, name, email, phone, job_id, is_sales) FROM stdin;
4	Rina Kurnia	rina@crm.com	0844444444	3	f
1	Budi Andika	budi@crm.com	0811111111	1	t
2	Tono Aminah	siti@crm.com	0822222222	2	t
3	Tri  Wijaya	andi@crm.com	0833333333	2	t
\.


--
-- Data for Name: hr_job; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.hr_job (job_id, name, description) FROM stdin;
1	Sales Manager	Manage sales team
2	Sales Executive	Handle customer and closing deals
3	Admin	Administrative tasks
\.


--
-- Data for Name: ir_attachment; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.ir_attachment (attachment_id, name, file_path, file_type, res_model, res_id, created_at, file_size) FROM stdin;
\.


--
-- Data for Name: lead_competitor_rel; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.lead_competitor_rel (lead_id, competitor_id) FROM stdin;
\.


--
-- Data for Name: mail_message; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.mail_message (message_id, res_model, res_id, author_id, body, message_type, created_at, subject) FROM stdin;
\.


--
-- Data for Name: res_currency; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.res_currency (currency_id, name, symbol, is_active, description, created_at) FROM stdin;
1	IDR	Rp	t	Rupiah Indonesia	2026-03-26 13:12:18.550137
\.


--
-- Data for Name: res_partner; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.res_partner (partner_id, company_type, parent_id, name, job_title, email, phone, address, is_customer, is_active, created_at, updated_at, mobile, website, tax_id, is_supplier, category_id) FROM stdin;
1	company	\N	PT Teknologi Nusantara		info@teknologinusantara.co.id	(021) 555-0192	Gedung Cyber, Jl. Kuningan Barat, Jakarta Selatan	t	t	2026-03-26 16:12:06.810004	2026-03-26 16:12:25.640893	081712345678901234	www.teknologinusantara.co.id	01.234.567.8-901.000	f	\N
2	person	1	Bapak Andi Susanto	IT Procurement Manager	andi.s@teknologinusantara.co.id	\N	\N	t	t	2026-03-26 16:15:56.906832	2026-03-26 16:15:56.906832	0812-3456-7890	\N	\N	f	\N
3	company	\N	CV Sentosa Printing		order@sentosaprinting.com	(022) 444-1234	Jl. Asia Afrika No. 45, Bandung	f	t	2026-03-26 16:17:08.290399	2026-03-26 16:17:08.290399	\N	\N	02.111.222.3-444.000	t	\N
4	person	\N	Ibu Siti Aminah	Freelance Digital Marketer	sitiaminah.digital@gmail.com	\N	\N	t	t	2026-03-26 16:18:19.75687	2026-03-26 16:18:19.75687	0856-1122-3344	\N	\N	t	\N
\.


--
-- Data for Name: res_partner_category; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.res_partner_category (category_id, name, color_code) FROM stdin;
1	VIP	#4f46e5
2	Retail	#3fee5c
3	Departement - Pemerintahan	#e7ec9c
\.


--
-- Data for Name: res_partner_contact; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.res_partner_contact (contact_id, partner_id, name, job_title, email, phone, is_primary) FROM stdin;
1	4	Bpk. Budi IT	IT Manager	budi@perusahaan-a.com	62812345678	t
2	4	Ibu Siti Finance	Finance Staff	siti@perusahaan-a.com	62812999888	f
3	1	Bpk. Heru Purchasing	Purchasing	heru@perusahaan-b.com	62855667788	t
4	4	test pic	OB	\N	08123123	f
5	1	tes partner contact 	infra	\N	0788781	f
\.


--
-- Data for Name: res_users; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.res_users (user_id, username, password, employee_id, is_active) FROM stdin;
1	budi	123456	1	t
2	siti	123456	2	t
3	andi	123456	3	t
4	rina	123456	4	t
\.


--
-- Data for Name: sales_targets; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.sales_targets (target_id, period, user_id, target_amount, notes, created_at) FROM stdin;
2	2026-04	2	350000000.00	target bulanan	2026-04-02 14:38:49.744424
1	2026-04	1	150000000.00	bulan april cuiiii	2026-04-02 14:33:32.031227
\.


--
-- Data for Name: sales_team; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.sales_team (team_id, name, team_leader_id, is_active, description, created_at, region, team_type, monthly_target, commission_rate, updated_at) FROM stdin;
2	Retail Jabar & Banten	102	t	Fokus door-to-door dan presentasi langsung ke end-user	2026-03-26 15:39:23.358975	Jawa Barat & Banten	B2C	500000000.00	5.00	2026-03-26 15:39:23.358975
1	Corporate B2B - Jakarta	102	t	Fokus mencari klien perusahaan multinasional dan BUMN	2026-03-26 15:37:46.158563	DKI Jakarta	B2B	2000000000.00	1.60	2026-03-26 15:39:37.852838
3	Telesales Nasional	103	t	Menghubungi (Follow up) semua prospek yang masuk dari iklan Instagram/Google (UTM Campaign)	2026-03-26 15:40:38.959047	Nasional (Remote)	Online	250000000.00	3.00	2026-03-26 15:40:38.959047
4	Distributor Luar Jawa	104	t	Menjaga hubungan dengan agen besar dan reseller di luar pulau Jawa	2026-03-26 15:41:41.551196	Sumatera & Sulawesi	Distributor	1500000000.00	2.00	2026-03-26 15:41:41.551196
\.


--
-- Data for Name: utm_campaign; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.utm_campaign (campaign_id, name, start_date, end_date, budget, expected_revenue, is_active, created_at, description, updated_at) FROM stdin;
1	promo lebaran 2026	2026-02-01	2026-06-30	5000000.00	50000000.00	t	2026-03-26 14:53:21.8324	Diskon 20% untuk semua layanan selama bulan Ramadhan	2026-03-26 14:53:21.8324
2	webinar_digital_marketing_q1	2026-03-26	2026-12-31	2000000.00	15000000.00	t	2026-03-26 14:54:19.900823	Pendaftaran webinar gratis untuk menjaring prospek (Lead Generation) di kuartal pertama	2026-03-26 14:54:19.900823
3	launching_jasa_seo_premium	2026-03-01	2027-02-01	10000000.00	100000000.00	t	2026-03-26 14:55:15.101008	Kampanye pengenalan paket layanan SEO baru untuk target perusahaan Enterprise	2026-03-26 14:55:15.101008
5	retargeting_website_visitor	2026-05-01	2026-10-31	5000000.00	25000000.00	t	2026-03-26 15:04:31.630453	Iklan yang terus berjalan sepanjang tahun, khusus menargetkan orang yang pernah mengunjungi website tapi belum beli	2026-03-26 15:04:40.84224
\.


--
-- Data for Name: utm_medium; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.utm_medium (medium_id, name, is_active, description, created_at) FROM stdin;
1	cpc	t	Cost Per Click - Iklan berbayar	2026-03-26 14:16:28.248609
2	social	t	Postingan organik sosmed	2026-03-26 14:16:51.100472
3	email	t	Email marketing / blast	2026-03-26 14:17:12.964414
4	banner	t	Iklan banner di website lain	2026-03-26 14:17:37.856112
\.


--
-- Data for Name: utm_source; Type: TABLE DATA; Schema: schema_crm; Owner: postgres
--

COPY schema_crm.utm_source (source_id, name, is_active, description, created_at) FROM stdin;
1	google	t	Trafik organik atau iklan berbayar dari Google Ads.	2026-03-26 13:46:46.209084
2	facebook	t	Klik dari postingan organik atau Meta/Facebook Ads	2026-03-26 13:47:22.786204
3	instagram	t	Klik dari link di bio IG atau Instagram Ads.	2026-03-26 13:47:44.633255
4	tiktok	t	Trafik dari konten video TikTok atau TikTok Ads.	2026-03-26 13:48:03.325957
\.


--
-- Data for Name: hr_log_salary_change; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_log_salary_change (dlog_id, dlog_employee_code, dlog_old_salary, dlog_new_salary, dlog_changed_at) FROM stdin;
\.


--
-- Data for Name: hr_mst_approval_flow; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_approval_flow (daflow_id, daflow_name, daflow_type) FROM stdin;
\.


--
-- Data for Name: hr_mst_attendance_rule; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_attendance_rule (datt_rule_id, dcomp_id, datt_late_penalty, datt_absent_penalty, datt_half_day_threshold) FROM stdin;
1	1	1000.00	150000.00	240
2	2	500.00	100000.00	240
\.


--
-- Data for Name: hr_mst_bpjs_setting; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_bpjs_setting (dbpjs_id, dbpjs_type, dbpjs_employee_rate, dbpjs_company_rate) FROM stdin;
1	KESEHATAN	1.00	4.00
2	JHT	2.00	3.70
3	JP	1.00	2.00
\.


--
-- Data for Name: hr_mst_company_config; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_company_config (dcomp_id, dcomp_code, dcomp_name, dcomp_tax_method, dcomp_bpjs_kes_rate, dcomp_bpjs_tk_rate, dcomp_is_active) FROM stdin;
1	HO-JKT	Kantor Pusat Jakarta	GROSS_UP	1.00	2.00	t
2	BR-SBY	Cabang Surabaya	GROSS	1.00	2.00	t
\.


--
-- Data for Name: hr_mst_company_setting; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_company_setting (dset_code, dset_value, dset_description) FROM stdin;
OVERTIME_DIVISOR	173.00	Pembagi upah lembur per jam (Standar UU)
WORKING_DAYS_MONTH	22.00	Rata-rata hari kerja dalam sebulan untuk potong absen
BPJS_KES_MAX_WAGE	12000000.00	Batas maksimal upah untuk perhitungan BPJS Kesehatan
BPJS_JP_MAX_WAGE	10042300.00	Batas maksimal upah untuk perhitungan Jaminan Pensiun (JP)
WORKING_HOURS_DAY	8.00	Standar jam kerja per hari (untuk hitung upah per jam / telat)
LATE_PENALTY_PER_MIN	1000.00	Nominal potongan keterlambatan per menit (Rupiah)
\.


--
-- Data for Name: hr_mst_department; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_department (dmdep_id, dmdep_code, dmdep_name, dmdep_is_active, dmdep_created_datetime, dmdep_created_by, dmdep_modified_datetime, dmdep_modified_by) FROM stdin;
\.


--
-- Data for Name: hr_mst_employee; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_employee (dmemp_id, dmemp_employee_code, dmemp_nik, dmemp_employee_name, dmemp_photo_path, dmemp_department_id, dmemp_position_id, dmemp_manager_id, dmemp_alamat, dmemp_no_telp, dmemp_email, dmemp_gender_id, dmemp_birth_date, dmemp_is_active, dmemp_created_datetime, dmemp_created_by, dmemp_modified_datetime, dmemp_modified_by, dmemp_grade_id, dcomp_id) FROM stdin;
6	EMP-001	bc001	EMP-001	\N	\N	\N	\N	\N	\N	\N	\N	\N	1	2026-04-16 14:56:06.780077	\N	\N	\N	2	1
7	EMP-002	bc002	EMP-002	\N	\N	\N	\N	\N	\N	\N	\N	\N	1	2026-04-16 14:56:06.780077	\N	\N	\N	1	1
\.


--
-- Data for Name: hr_mst_employee_payroll_config; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_employee_payroll_config (depc_id, depc_employee_code, depc_is_bpjs_kes, depc_is_bpjs_tk, depc_is_taxable, depc_is_overtime_eligible) FROM stdin;
1	EMP-001	t	t	t	f
2	EMP-002	t	t	t	t
\.


--
-- Data for Name: hr_mst_employee_tax; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_employee_tax (detax_id, detax_employee_code, detax_npwp, detax_ptkp_status) FROM stdin;
1	EMP-001	12.345.678.9-012.000	K/1
2	EMP-002	98.765.432.1-098.000	TK/0
\.


--
-- Data for Name: hr_mst_formula; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_formula (dform_id, dform_code, dform_name, dform_expression, dform_description) FROM stdin;
1	TUNJ_JABATAN	Tunjangan Jabatan 10%	( basic_salary * 0.1 )	\N
2	LEMBUR_HOLIDAY	Lembur Hari Libur	( basic_salary / 173 ) * overtime_hours * 2	\N
3	POT_MANGKIR	Potongan Absen/Mangkir	( basic_salary / working_days ) * absent_days	\N
\.


--
-- Data for Name: hr_mst_holiday; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_holiday (dmhol_id, dmhol_date, dmhol_description, dmhol_is_active, dmhol_created_datetime, dmhol_created_by) FROM stdin;
\.


--
-- Data for Name: hr_mst_job_grade; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_job_grade (dgrade_id, dgrade_name, dgrade_min_salary, dgrade_max_salary) FROM stdin;
1	Staff IT	5000000.00	15000000.00
2	Supervisor IT	10000000.00	25000000.00
3	Staff IT	5000000.00	15000000.00
4	Supervisor IT	10000000.00	25000000.00
\.


--
-- Data for Name: hr_mst_leave_type; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_leave_type (dmlty_id, dmlty_code, dmlty_name, dmlty_default_days, dmlty_is_active, dmlty_created_datetime, dmlty_created_by) FROM stdin;
\.


--
-- Data for Name: hr_mst_loan_type; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_loan_type (dloant_id, dloant_code, dloant_name, dloant_interest_rate, dloant_max_tenor, dloant_is_active) FROM stdin;
1	KASBON	Kasbon Darurat (Potong Gaji Bulan Depan)	0.00	1	t
2	KTA	Kredit Tanpa Agunan Karyawan	1.00	12	t
\.


--
-- Data for Name: hr_mst_payroll_period; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_payroll_period (dper_id, dper_code, dper_name, dper_start_date, dper_end_date, dper_status, dper_created_datetime, dper_created_by, dper_attendance_start_date, dper_attendance_end_date, dper_pay_date) FROM stdin;
1	PR-2026-04	Payroll April 2026	2026-03-26	2026-04-25	OPEN	2026-04-16 14:49:31.542096	SYSTEM	2026-03-26	2026-04-25	2026-04-26
\.


--
-- Data for Name: hr_mst_payroll_rule; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_payroll_rule (drule_id, drule_name, drule_type, drule_formula, drule_is_active, drule_created_datetime) FROM stdin;
\.


--
-- Data for Name: hr_mst_position; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_position (dmpos_id, dmpos_code, dmpos_name, dmpos_is_active, dmpos_created_datetime, dmpos_created_by, dmpos_modified_datetime, dmpos_modified_by) FROM stdin;
\.


--
-- Data for Name: hr_mst_ptkp; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_ptkp (dptkp_id, dptkp_code, dptkp_amount, dptkp_description) FROM stdin;
1	TK/0	54000000.00	Tidak Kawin, 0 Tanggungan
2	TK/1	58500000.00	Tidak Kawin, 1 Tanggungan
3	K/0	58500000.00	Kawin, 0 Tanggungan
4	TK/2	63000000.00	Tidak Kawin, 2 Tanggungan
5	K/1	63000000.00	Kawin, 1 Tanggungan
6	TK/3	67500000.00	Tidak Kawin, 3 Tanggungan
7	K/2	67500000.00	Kawin, 2 Tanggungan
8	K/3	72000000.00	Kawin, 3 Tanggungan
\.


--
-- Data for Name: hr_mst_salary_component; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_salary_component (dmsc_id, dmsc_code, dmsc_name, dmsc_category, dmsc_type, dmsc_is_taxable, dmsc_is_bpjs, dmsc_is_active, dmsc_created_datetime, dmsc_created_by) FROM stdin;
\.


--
-- Data for Name: hr_mst_shift; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_shift (dshift_id, dshift_name, dshift_start_time, dshift_end_time, dshift_is_night, dshift_created_datetime) FROM stdin;
\.


--
-- Data for Name: hr_mst_tax_rate; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_mst_tax_rate (dtax_id, dtax_name, dtax_rate, dtax_min_income, dtax_max_income) FROM stdin;
\.


--
-- Data for Name: hr_txn_approval; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_approval (dapp_id, dapp_ref_id, dapp_ref_type, dapp_approver, dapp_status, dapp_approved_date) FROM stdin;
\.


--
-- Data for Name: hr_txn_attendance; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_attendance (dmatn_id, dmatn_employee_code, dmatn_date, dmatn_clock_in, dmatn_clock_out, dmatn_work_hours, dmatn_status, dmatn_created_datetime) FROM stdin;
\.


--
-- Data for Name: hr_txn_career_history; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_career_history (dmcar_id, dmcar_employee_code, dmcar_type, dmcar_old_department_id, dmcar_new_department_id, dmcar_old_position_id, dmcar_new_position_id, dmcar_effective_date, dmcar_reason, dmcar_status, dmcar_created_datetime, dmcar_created_by) FROM stdin;
\.


--
-- Data for Name: hr_txn_contract; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_contract (dmcon_id, dmcon_employee_code, dmcon_contract_no, dmcon_employment_type, dmcon_start_date, dmcon_end_date, dmcon_status, dmcon_created_datetime, dmcon_created_by, dmcon_modified_datetime, dmcon_modified_by) FROM stdin;
\.


--
-- Data for Name: hr_txn_document; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_document (dmdoc_id, dmdoc_employee_code, dmdoc_type, dmdoc_no, dmdoc_file_path, dmdoc_expiry_date, dmdoc_created_datetime, dmdoc_created_by) FROM stdin;
\.


--
-- Data for Name: hr_txn_employee_payroll_rule; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_employee_payroll_rule (depr_id, depr_employee_code, depr_rule_id) FROM stdin;
\.


--
-- Data for Name: hr_txn_employee_salary; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_employee_salary (dmsal_id, dmsal_employee_code, dmsal_basic_salary, dmsal_bank_name, dmsal_bank_account_no, dmsal_effective_start_date, dmsal_effective_end_date, dmsal_is_active, dmsal_created_datetime, dmsal_created_by, dmsal_payment_frequency) FROM stdin;
5	EMP-001	12000000.00	\N	\N	2026-01-01	\N	1	2026-04-16 14:56:12.760366	SYSTEM	MONTHLY
6	EMP-002	8000000.00	\N	\N	2026-01-01	\N	1	2026-04-16 14:56:12.760366	SYSTEM	MONTHLY
\.


--
-- Data for Name: hr_txn_employee_salary_detail; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_employee_salary_detail (dmsald_id, dmsald_salary_id, dmsald_component_id, dmsald_amount) FROM stdin;
\.


--
-- Data for Name: hr_txn_employee_shift; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_employee_shift (deshift_id, deshift_employee_code, deshift_shift_id, deshift_date, deshift_created_datetime) FROM stdin;
\.


--
-- Data for Name: hr_txn_leave_balance; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_leave_balance (dmlbal_id, dmlbal_employee_code, dmlbal_leave_type_id, dmlbal_period_year, dmlbal_allocated_days, dmlbal_used_days, dmlbal_created_datetime) FROM stdin;
\.


--
-- Data for Name: hr_txn_leave_request; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_leave_request (dmlreq_id, dmlreq_employee_code, dmlreq_leave_type_id, dmlreq_start_date, dmlreq_end_date, dmlreq_total_days, dmlreq_reason, dmlreq_status, dmlreq_approved_by, dmlreq_created_datetime, dmlreq_created_by, dmlreq_modified_datetime, dmlreq_modified_by) FROM stdin;
\.


--
-- Data for Name: hr_txn_loan; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_loan (dmlon_id, dmlon_employee_code, dmlon_loan_date, dmlon_total_amount, dmlon_installment_amount, dmlon_tenor, dmlon_remaining_balance, dmlon_status, dmlon_created_datetime, dmlon_created_by, dloant_id) FROM stdin;
\.


--
-- Data for Name: hr_txn_overtime; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_overtime (dmovt_id, dmovt_employee_code, dmovt_attendance_id, dmovt_request_date, dmovt_start_time, dmovt_end_time, dmovt_total_hours, dmovt_reason, dmovt_status, dmovt_approved_by, dmovt_created_datetime, dmovt_created_by, dmovt_modified_datetime, dmovt_modified_by, dmovt_is_holiday) FROM stdin;
\.


--
-- Data for Name: hr_txn_payslip; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_payslip (dmps_id, dmps_employee_code, dmps_total_earnings, dmps_total_deductions, dmps_net_pay, dmps_status, dmps_created_datetime, dmps_created_by, dmps_period_start_date, dmps_period_end_date, dmps_payment_frequency, dper_id) FROM stdin;
1	EMP-001	12000000.00	120000.00	11880000.00	DRAFT	2026-04-16 14:57:34.78211	HR_ADMIN	2026-03-26	2026-04-25	MONTHLY	1
2	EMP-002	8000000.00	80000.00	7920000.00	DRAFT	2026-04-16 14:57:34.78211	HR_ADMIN	2026-03-26	2026-04-25	MONTHLY	1
\.


--
-- Data for Name: hr_txn_payslip_line; Type: TABLE DATA; Schema: schema_hrd; Owner: postgres
--

COPY schema_hrd.hr_txn_payslip_line (dmpsl_id, dmpsl_payslip_id, dmpsl_component_id, dmpsl_category, dmpsl_description, dmpsl_amount) FROM stdin;
1	1	\N	EARNING	Gaji Pokok	12000000.00
2	1	\N	DEDUCTION	Potongan BPJS Kesehatan	120000.00
3	2	\N	EARNING	Gaji Pokok	8000000.00
4	2	\N	DEDUCTION	Potongan BPJS Kesehatan	80000.00
\.


--
-- Data for Name: admin_event_entity; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.admin_event_entity (id, admin_event_time, realm_id, operation_type, auth_realm_id, auth_client_id, auth_user_id, ip_address, resource_path, representation, error, resource_type, details_json) FROM stdin;
\.


--
-- Data for Name: associated_policy; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.associated_policy (policy_id, associated_policy_id) FROM stdin;
\.


--
-- Data for Name: auth_session; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.auth_session (root_auth_session_id, tab_id, client_uuid, auth_user_id, "timestamp", version, redirect_uri, action, protocol, client_scopes, execution_status, client_notes, auth_notes, required_actions, user_session_notes) FROM stdin;
\.


--
-- Data for Name: authentication_execution; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.authentication_execution (id, alias, authenticator, realm_id, flow_id, requirement, priority, authenticator_flow, auth_flow_id, auth_config) FROM stdin;
63df0a26-cd74-4947-b6b8-fae38397e44b	\N	auth-cookie	331e6113-4db4-4433-997e-09db1350e12a	11c99cf1-51bb-4b35-936e-08120938e064	2	10	f	\N	\N
3cbb73ed-8e56-4589-9b32-e59a9488bab0	\N	auth-spnego	331e6113-4db4-4433-997e-09db1350e12a	11c99cf1-51bb-4b35-936e-08120938e064	3	20	f	\N	\N
c5b6dd81-7545-4dd0-9349-8c344843e872	\N	identity-provider-redirector	331e6113-4db4-4433-997e-09db1350e12a	11c99cf1-51bb-4b35-936e-08120938e064	2	25	f	\N	\N
dbdfa319-d74e-4024-9038-cc76baef71a0	\N	\N	331e6113-4db4-4433-997e-09db1350e12a	11c99cf1-51bb-4b35-936e-08120938e064	2	30	t	d2f9f9f4-ee4a-4739-821c-8b560e537677	\N
b470a88b-cec3-4f03-b338-a547bbeab604	\N	auth-username-password-form	331e6113-4db4-4433-997e-09db1350e12a	d2f9f9f4-ee4a-4739-821c-8b560e537677	0	10	f	\N	\N
78197c1f-dae0-4305-a54e-b3ed0547cded	\N	\N	331e6113-4db4-4433-997e-09db1350e12a	d2f9f9f4-ee4a-4739-821c-8b560e537677	1	20	t	f25cbf37-bf78-4838-8d34-5f7ff86d83e7	\N
4ab84109-ffc5-47f7-aca2-cf753f37fb73	\N	conditional-user-configured	331e6113-4db4-4433-997e-09db1350e12a	f25cbf37-bf78-4838-8d34-5f7ff86d83e7	0	10	f	\N	\N
57fd9be8-72eb-4315-bb56-f9a6bbee7b34	\N	conditional-credential	331e6113-4db4-4433-997e-09db1350e12a	f25cbf37-bf78-4838-8d34-5f7ff86d83e7	0	20	f	\N	d0ddc5f6-8e08-4d97-b81c-347433c9cc04
638da2c7-e8ac-4776-9c3c-1672afef9e79	\N	auth-otp-form	331e6113-4db4-4433-997e-09db1350e12a	f25cbf37-bf78-4838-8d34-5f7ff86d83e7	2	30	f	\N	\N
5fad75cd-e9fc-4dec-b5f1-628ced6ce86b	\N	webauthn-authenticator	331e6113-4db4-4433-997e-09db1350e12a	f25cbf37-bf78-4838-8d34-5f7ff86d83e7	3	40	f	\N	\N
279a343d-2335-4cb2-a379-d774e81f69a9	\N	auth-recovery-authn-code-form	331e6113-4db4-4433-997e-09db1350e12a	f25cbf37-bf78-4838-8d34-5f7ff86d83e7	3	50	f	\N	\N
14ce3004-6e3f-4848-99ed-edea8fab35ec	\N	direct-grant-validate-username	331e6113-4db4-4433-997e-09db1350e12a	acf00bd3-ff09-4e6a-96af-3fbe054f6b21	0	10	f	\N	\N
c101bd3b-473a-4302-bac2-d2f25fb62a7c	\N	direct-grant-validate-password	331e6113-4db4-4433-997e-09db1350e12a	acf00bd3-ff09-4e6a-96af-3fbe054f6b21	0	20	f	\N	\N
51b8094f-2ce5-40b6-97e2-c272b0c71e21	\N	\N	331e6113-4db4-4433-997e-09db1350e12a	acf00bd3-ff09-4e6a-96af-3fbe054f6b21	1	30	t	cfedfa8e-98a5-4fc7-941a-f5dd7214efa5	\N
4182d3f9-8749-49df-91ca-5e15132ec15e	\N	conditional-user-configured	331e6113-4db4-4433-997e-09db1350e12a	cfedfa8e-98a5-4fc7-941a-f5dd7214efa5	0	10	f	\N	\N
6f79302e-1185-4a88-9728-a8892a11c651	\N	direct-grant-validate-otp	331e6113-4db4-4433-997e-09db1350e12a	cfedfa8e-98a5-4fc7-941a-f5dd7214efa5	0	20	f	\N	\N
14edc3a4-d5fb-45f0-9f47-fa34e6576d08	\N	registration-page-form	331e6113-4db4-4433-997e-09db1350e12a	7badefb3-ac43-43ba-8028-608c6f6438e2	0	10	t	ecb0ddb9-a3d7-47f2-904f-270d05d6c73c	\N
873a6f2d-9b27-410c-97a0-8f7f57038d74	\N	registration-user-creation	331e6113-4db4-4433-997e-09db1350e12a	ecb0ddb9-a3d7-47f2-904f-270d05d6c73c	0	20	f	\N	\N
a695eac7-d019-4d77-a312-4d9b8c973695	\N	registration-password-action	331e6113-4db4-4433-997e-09db1350e12a	ecb0ddb9-a3d7-47f2-904f-270d05d6c73c	0	50	f	\N	\N
0166139f-ca34-44a1-b2f6-74711e3efda4	\N	registration-recaptcha-action	331e6113-4db4-4433-997e-09db1350e12a	ecb0ddb9-a3d7-47f2-904f-270d05d6c73c	3	60	f	\N	\N
56e26513-94cd-4682-a8b4-917d18920978	\N	registration-terms-and-conditions	331e6113-4db4-4433-997e-09db1350e12a	ecb0ddb9-a3d7-47f2-904f-270d05d6c73c	3	70	f	\N	\N
e80d9b82-ca85-4317-a618-b07f28931545	\N	reset-credentials-choose-user	331e6113-4db4-4433-997e-09db1350e12a	e4ba5024-be4b-49f9-9be8-7de0ec713ca3	0	10	f	\N	\N
13090cd2-324a-4ee6-8689-d39534c4f2d5	\N	reset-credential-email	331e6113-4db4-4433-997e-09db1350e12a	e4ba5024-be4b-49f9-9be8-7de0ec713ca3	0	20	f	\N	\N
f715a728-b1ef-423d-8565-0fb2b0bff311	\N	reset-password	331e6113-4db4-4433-997e-09db1350e12a	e4ba5024-be4b-49f9-9be8-7de0ec713ca3	0	30	f	\N	\N
05f81b05-8eb4-451b-a7dc-db179d90cc58	\N	\N	331e6113-4db4-4433-997e-09db1350e12a	e4ba5024-be4b-49f9-9be8-7de0ec713ca3	1	40	t	5ef484be-8ef0-4657-a527-dee1a41b47ab	\N
a7474866-59d7-4ec9-9ced-25e173f4f298	\N	conditional-user-configured	331e6113-4db4-4433-997e-09db1350e12a	5ef484be-8ef0-4657-a527-dee1a41b47ab	0	10	f	\N	\N
9cd5f975-d9bc-4052-9e51-7de39c3cffe5	\N	reset-otp	331e6113-4db4-4433-997e-09db1350e12a	5ef484be-8ef0-4657-a527-dee1a41b47ab	0	20	f	\N	\N
01e896c4-94e6-4b4b-a892-71013c4c721e	\N	client-secret	331e6113-4db4-4433-997e-09db1350e12a	d0aca77b-fb6b-494c-8602-c984ef78120d	2	10	f	\N	\N
416428f8-448b-43cb-8ea7-68bf9fe5e8ad	\N	client-jwt	331e6113-4db4-4433-997e-09db1350e12a	d0aca77b-fb6b-494c-8602-c984ef78120d	2	20	f	\N	\N
a66c9407-2cec-4079-b5d6-19efb769246f	\N	client-secret-jwt	331e6113-4db4-4433-997e-09db1350e12a	d0aca77b-fb6b-494c-8602-c984ef78120d	2	30	f	\N	\N
1e13c4d0-229b-4eb4-8950-a1999120bbc0	\N	client-x509	331e6113-4db4-4433-997e-09db1350e12a	d0aca77b-fb6b-494c-8602-c984ef78120d	2	40	f	\N	\N
f661a94d-f85f-43f4-9201-ce68284b5600	\N	federated-jwt	331e6113-4db4-4433-997e-09db1350e12a	d0aca77b-fb6b-494c-8602-c984ef78120d	2	50	f	\N	\N
2629169b-eb64-4673-9a8e-63a8a69a994e	\N	idp-review-profile	331e6113-4db4-4433-997e-09db1350e12a	306af93f-cb5f-49a9-9533-947f7df994b3	0	10	f	\N	4d32c0d0-84c2-4ff9-a0c1-dafc3e01a520
9224e46e-017f-4fca-8da2-55c945563476	\N	\N	331e6113-4db4-4433-997e-09db1350e12a	306af93f-cb5f-49a9-9533-947f7df994b3	0	20	t	5d6e3938-655c-41cb-bb90-dbf5ccda4bbe	\N
e55e3c44-68c9-4ab3-8531-c409e1b20ba0	\N	idp-create-user-if-unique	331e6113-4db4-4433-997e-09db1350e12a	5d6e3938-655c-41cb-bb90-dbf5ccda4bbe	2	10	f	\N	b48c7109-adec-4a69-a813-27b2a2da237e
e9e6e765-73df-4340-81bd-e1d9bb572c71	\N	\N	331e6113-4db4-4433-997e-09db1350e12a	5d6e3938-655c-41cb-bb90-dbf5ccda4bbe	2	20	t	352bf0c2-8759-419a-a402-e2b123a077cc	\N
79ab7cf6-e00e-450b-8d63-a20cc61aad2f	\N	idp-confirm-link	331e6113-4db4-4433-997e-09db1350e12a	352bf0c2-8759-419a-a402-e2b123a077cc	0	10	f	\N	\N
8e94fea6-db6f-4bbd-a83e-6a5033cd2f20	\N	\N	331e6113-4db4-4433-997e-09db1350e12a	352bf0c2-8759-419a-a402-e2b123a077cc	0	20	t	95072ae6-e5b9-4bf9-8d26-343a82f2f097	\N
fd057346-70ae-489f-901f-8fd890d18174	\N	idp-email-verification	331e6113-4db4-4433-997e-09db1350e12a	95072ae6-e5b9-4bf9-8d26-343a82f2f097	2	10	f	\N	\N
0d0a5a0e-7b5d-437f-bac9-e00ae366b194	\N	\N	331e6113-4db4-4433-997e-09db1350e12a	95072ae6-e5b9-4bf9-8d26-343a82f2f097	2	20	t	59c3ee72-e38c-4a2c-ba36-a22e951b7c7c	\N
0c4f095c-668d-42f9-aef0-c9fffc66857c	\N	idp-username-password-form	331e6113-4db4-4433-997e-09db1350e12a	59c3ee72-e38c-4a2c-ba36-a22e951b7c7c	0	10	f	\N	\N
f5c5a5f8-d56a-4780-85a1-06d37c7eb289	\N	\N	331e6113-4db4-4433-997e-09db1350e12a	59c3ee72-e38c-4a2c-ba36-a22e951b7c7c	1	20	t	d7ea1bbd-35bc-4b2b-ab0d-4e79f73fb78a	\N
67a06497-2800-40a2-aba2-bd170796ebea	\N	conditional-user-configured	331e6113-4db4-4433-997e-09db1350e12a	d7ea1bbd-35bc-4b2b-ab0d-4e79f73fb78a	0	10	f	\N	\N
47fe4044-5d40-4a03-90c8-e9356684bab4	\N	conditional-credential	331e6113-4db4-4433-997e-09db1350e12a	d7ea1bbd-35bc-4b2b-ab0d-4e79f73fb78a	0	20	f	\N	1ef3b979-a1e5-4291-844c-a8350c748ba2
87144525-32ce-4cd3-a911-29efc9ff3926	\N	auth-otp-form	331e6113-4db4-4433-997e-09db1350e12a	d7ea1bbd-35bc-4b2b-ab0d-4e79f73fb78a	2	30	f	\N	\N
d329865b-45c7-4481-943d-1fc027204bf5	\N	webauthn-authenticator	331e6113-4db4-4433-997e-09db1350e12a	d7ea1bbd-35bc-4b2b-ab0d-4e79f73fb78a	3	40	f	\N	\N
9ba9d668-5be3-45b1-a20e-7b8e99f9c8e9	\N	auth-recovery-authn-code-form	331e6113-4db4-4433-997e-09db1350e12a	d7ea1bbd-35bc-4b2b-ab0d-4e79f73fb78a	3	50	f	\N	\N
98e4b005-ce71-4bbe-9f6f-9cb0e8b64066	\N	http-basic-authenticator	331e6113-4db4-4433-997e-09db1350e12a	723ded02-5b41-4241-bad8-e85071c97b03	0	10	f	\N	\N
d936f9f5-ad3a-46d9-b42e-df87264d712e	\N	docker-http-basic-authenticator	331e6113-4db4-4433-997e-09db1350e12a	193dd51a-cea0-4619-ade0-2780e330204a	0	10	f	\N	\N
82d2ecdc-2731-4d01-8d7e-dd7336e167ba	\N	auth-cookie	5928e5d4-c400-4150-9107-da98acace8cf	509d7aad-da1f-4abd-aab1-1a7478101578	2	10	f	\N	\N
d9ecb2b1-5be6-4c50-abb5-6898f1f17d19	\N	auth-spnego	5928e5d4-c400-4150-9107-da98acace8cf	509d7aad-da1f-4abd-aab1-1a7478101578	3	20	f	\N	\N
fc5a2a1d-c256-4ea5-9535-58d18b59521b	\N	identity-provider-redirector	5928e5d4-c400-4150-9107-da98acace8cf	509d7aad-da1f-4abd-aab1-1a7478101578	2	25	f	\N	\N
cf9d1f0e-03d8-47fe-a136-a3ae1a86b507	\N	\N	5928e5d4-c400-4150-9107-da98acace8cf	509d7aad-da1f-4abd-aab1-1a7478101578	2	30	t	badcebd3-fceb-44ca-875a-00b3518be892	\N
425f45c6-3ee6-4caf-9fab-f83586712c43	\N	auth-username-password-form	5928e5d4-c400-4150-9107-da98acace8cf	badcebd3-fceb-44ca-875a-00b3518be892	0	10	f	\N	\N
4c982dc9-6834-4403-8da1-0a284ac1ecfb	\N	\N	5928e5d4-c400-4150-9107-da98acace8cf	badcebd3-fceb-44ca-875a-00b3518be892	1	20	t	ed515fe6-8a07-46a7-b361-1e84dcf79915	\N
800d8537-75f1-48f5-b445-615c09d77a2a	\N	conditional-user-configured	5928e5d4-c400-4150-9107-da98acace8cf	ed515fe6-8a07-46a7-b361-1e84dcf79915	0	10	f	\N	\N
3a176e05-0c51-4f5b-a26f-721a9fafa34e	\N	conditional-credential	5928e5d4-c400-4150-9107-da98acace8cf	ed515fe6-8a07-46a7-b361-1e84dcf79915	0	20	f	\N	132f8184-413f-4cbd-a095-a3c536f4080f
e05002e7-84ed-496a-a12e-6346baba02e8	\N	auth-otp-form	5928e5d4-c400-4150-9107-da98acace8cf	ed515fe6-8a07-46a7-b361-1e84dcf79915	2	30	f	\N	\N
d46ded26-6bd3-4ee3-ae6c-684e274f20e6	\N	webauthn-authenticator	5928e5d4-c400-4150-9107-da98acace8cf	ed515fe6-8a07-46a7-b361-1e84dcf79915	3	40	f	\N	\N
6072ba73-becd-41e6-afd3-4447ce645102	\N	auth-recovery-authn-code-form	5928e5d4-c400-4150-9107-da98acace8cf	ed515fe6-8a07-46a7-b361-1e84dcf79915	3	50	f	\N	\N
a7bcaaf7-f9ff-4ab8-8d47-a95cb99567f8	\N	\N	5928e5d4-c400-4150-9107-da98acace8cf	509d7aad-da1f-4abd-aab1-1a7478101578	2	26	t	0118d63c-22f2-4e1f-949b-e8dfd166ea80	\N
cee3ef69-cde2-4eea-aad4-99c9c87b1079	\N	\N	5928e5d4-c400-4150-9107-da98acace8cf	0118d63c-22f2-4e1f-949b-e8dfd166ea80	1	10	t	ea45eba4-61b1-4b17-bae7-a9439f8f101b	\N
291e9045-885b-493d-8546-cdfb70b25188	\N	conditional-user-configured	5928e5d4-c400-4150-9107-da98acace8cf	ea45eba4-61b1-4b17-bae7-a9439f8f101b	0	10	f	\N	\N
3f1b85e8-557a-4a15-aaaf-ec3bd6a2cac3	\N	organization	5928e5d4-c400-4150-9107-da98acace8cf	ea45eba4-61b1-4b17-bae7-a9439f8f101b	2	20	f	\N	\N
ba4fb940-ec1f-4142-8c54-7420925c8730	\N	direct-grant-validate-username	5928e5d4-c400-4150-9107-da98acace8cf	34d95689-1631-4af2-b2f3-82c538c316f2	0	10	f	\N	\N
eeb4455e-f816-4a3c-8180-aaabefe19dc0	\N	direct-grant-validate-password	5928e5d4-c400-4150-9107-da98acace8cf	34d95689-1631-4af2-b2f3-82c538c316f2	0	20	f	\N	\N
2e128556-28bc-4302-90dd-66ce8d31b45a	\N	\N	5928e5d4-c400-4150-9107-da98acace8cf	34d95689-1631-4af2-b2f3-82c538c316f2	1	30	t	1bcb4447-0741-4aaa-9c1f-1011511c52bc	\N
9f26f443-2f7c-4279-96f7-b798c5c4a48a	\N	conditional-user-configured	5928e5d4-c400-4150-9107-da98acace8cf	1bcb4447-0741-4aaa-9c1f-1011511c52bc	0	10	f	\N	\N
2eec4a82-8fdd-4861-bb2f-6d14a97cd51c	\N	direct-grant-validate-otp	5928e5d4-c400-4150-9107-da98acace8cf	1bcb4447-0741-4aaa-9c1f-1011511c52bc	0	20	f	\N	\N
0b5d97c4-27f3-4032-99c0-abc7bfb498ab	\N	registration-page-form	5928e5d4-c400-4150-9107-da98acace8cf	d0baeced-93df-464d-b388-18f8b2629324	0	10	t	a15100aa-9bd7-4a3d-b66d-e5b6d074f500	\N
553fa514-db97-4dd4-afc3-d87d6efe2716	\N	registration-user-creation	5928e5d4-c400-4150-9107-da98acace8cf	a15100aa-9bd7-4a3d-b66d-e5b6d074f500	0	20	f	\N	\N
769d7aad-584e-41fd-baaa-e3cb9c527605	\N	registration-password-action	5928e5d4-c400-4150-9107-da98acace8cf	a15100aa-9bd7-4a3d-b66d-e5b6d074f500	0	50	f	\N	\N
1dccb1c4-99a8-4cbf-92fb-86978304d7d6	\N	registration-recaptcha-action	5928e5d4-c400-4150-9107-da98acace8cf	a15100aa-9bd7-4a3d-b66d-e5b6d074f500	3	60	f	\N	\N
433fd683-478a-433d-b83a-4eb492442363	\N	registration-terms-and-conditions	5928e5d4-c400-4150-9107-da98acace8cf	a15100aa-9bd7-4a3d-b66d-e5b6d074f500	3	70	f	\N	\N
d47b569b-c6e6-48e8-8945-ee6e218c9f4e	\N	reset-credentials-choose-user	5928e5d4-c400-4150-9107-da98acace8cf	c1cc7640-d4e9-48e7-b062-aced0771c2b4	0	10	f	\N	\N
27c33d83-f346-4ebc-8be4-1a11e7174c89	\N	reset-credential-email	5928e5d4-c400-4150-9107-da98acace8cf	c1cc7640-d4e9-48e7-b062-aced0771c2b4	0	20	f	\N	\N
8d00d146-d668-4cd5-8996-68e4f67f486c	\N	reset-password	5928e5d4-c400-4150-9107-da98acace8cf	c1cc7640-d4e9-48e7-b062-aced0771c2b4	0	30	f	\N	\N
95750f42-d66c-43ae-b80b-bc5a36eedcc5	\N	\N	5928e5d4-c400-4150-9107-da98acace8cf	c1cc7640-d4e9-48e7-b062-aced0771c2b4	1	40	t	6a7ac786-007a-44dc-91f2-45b01f233881	\N
dd0e3749-c522-4387-a49b-f838d346e050	\N	conditional-user-configured	5928e5d4-c400-4150-9107-da98acace8cf	6a7ac786-007a-44dc-91f2-45b01f233881	0	10	f	\N	\N
b3a30c12-8031-483b-bbed-66eb4b2d9a5c	\N	reset-otp	5928e5d4-c400-4150-9107-da98acace8cf	6a7ac786-007a-44dc-91f2-45b01f233881	0	20	f	\N	\N
b2ee6311-9a5e-4f51-a59e-79d0a0bb22ec	\N	client-secret	5928e5d4-c400-4150-9107-da98acace8cf	9770201c-6ffe-4089-adab-d16b13fdcfd6	2	10	f	\N	\N
c498c76e-468c-4c1d-a3c4-f6406d05b4f8	\N	client-jwt	5928e5d4-c400-4150-9107-da98acace8cf	9770201c-6ffe-4089-adab-d16b13fdcfd6	2	20	f	\N	\N
022c22b9-e63c-4355-ba4a-074231b4d1fa	\N	client-secret-jwt	5928e5d4-c400-4150-9107-da98acace8cf	9770201c-6ffe-4089-adab-d16b13fdcfd6	2	30	f	\N	\N
a034c207-4437-4ef1-b23f-abf5b3beffd9	\N	client-x509	5928e5d4-c400-4150-9107-da98acace8cf	9770201c-6ffe-4089-adab-d16b13fdcfd6	2	40	f	\N	\N
82826077-e042-499e-b0c3-31e28de0d7f8	\N	federated-jwt	5928e5d4-c400-4150-9107-da98acace8cf	9770201c-6ffe-4089-adab-d16b13fdcfd6	2	50	f	\N	\N
4570fad2-0b3e-4e48-bdc8-dd07b2d19b6d	\N	idp-review-profile	5928e5d4-c400-4150-9107-da98acace8cf	e6b61eb8-2edd-45b8-b81a-23cd657e397d	0	10	f	\N	85424540-624c-4c3a-bfa6-3e6d8a99889a
8b5d640e-5c00-417d-87bb-366c186b17c3	\N	\N	5928e5d4-c400-4150-9107-da98acace8cf	e6b61eb8-2edd-45b8-b81a-23cd657e397d	0	20	t	15b3a4b0-6dc6-4349-a977-b96bb61d9d10	\N
bbabf641-62df-40eb-b927-1e6152ff9634	\N	idp-create-user-if-unique	5928e5d4-c400-4150-9107-da98acace8cf	15b3a4b0-6dc6-4349-a977-b96bb61d9d10	2	10	f	\N	a2a51cb2-6135-41f4-a081-254ad98d2300
aeec874a-7b9e-42b3-97d8-5b23fc565160	\N	\N	5928e5d4-c400-4150-9107-da98acace8cf	15b3a4b0-6dc6-4349-a977-b96bb61d9d10	2	20	t	a8d0064b-ed5c-45ea-adcd-8887a460cf73	\N
de6e3a4d-7c3b-47a3-a945-105d47e88e0c	\N	idp-confirm-link	5928e5d4-c400-4150-9107-da98acace8cf	a8d0064b-ed5c-45ea-adcd-8887a460cf73	0	10	f	\N	\N
67e054e6-71d0-4a2c-858c-94c59886c0c5	\N	\N	5928e5d4-c400-4150-9107-da98acace8cf	a8d0064b-ed5c-45ea-adcd-8887a460cf73	0	20	t	dcb3c4c0-06f8-41e1-bd8b-e65e83e13495	\N
493814b2-55f5-45c0-9c79-d02c2f0129b7	\N	idp-email-verification	5928e5d4-c400-4150-9107-da98acace8cf	dcb3c4c0-06f8-41e1-bd8b-e65e83e13495	2	10	f	\N	\N
93f3186e-0e0c-4cd2-b10e-36342cd8224a	\N	\N	5928e5d4-c400-4150-9107-da98acace8cf	dcb3c4c0-06f8-41e1-bd8b-e65e83e13495	2	20	t	10b3c034-1d3e-4a1a-9da1-16c343b9f376	\N
9655b646-55f7-4e6b-8cd9-fa1e318fe281	\N	idp-username-password-form	5928e5d4-c400-4150-9107-da98acace8cf	10b3c034-1d3e-4a1a-9da1-16c343b9f376	0	10	f	\N	\N
7122b56e-7b75-46d7-9661-62c7dbc3aa38	\N	\N	5928e5d4-c400-4150-9107-da98acace8cf	10b3c034-1d3e-4a1a-9da1-16c343b9f376	1	20	t	c44f6235-0962-46d7-8869-7a5998115093	\N
a2dada98-f972-4e54-a968-457d6ebf7c2f	\N	conditional-user-configured	5928e5d4-c400-4150-9107-da98acace8cf	c44f6235-0962-46d7-8869-7a5998115093	0	10	f	\N	\N
cc9dc2bc-adad-457a-aa6c-3a9e26f967d0	\N	conditional-credential	5928e5d4-c400-4150-9107-da98acace8cf	c44f6235-0962-46d7-8869-7a5998115093	0	20	f	\N	f3625cae-e260-4a03-8674-419c79211ca1
77a55374-5769-4264-833f-9575d785d3b1	\N	auth-otp-form	5928e5d4-c400-4150-9107-da98acace8cf	c44f6235-0962-46d7-8869-7a5998115093	2	30	f	\N	\N
357e6a15-cd7d-46d2-b6bd-edb59fff13b6	\N	webauthn-authenticator	5928e5d4-c400-4150-9107-da98acace8cf	c44f6235-0962-46d7-8869-7a5998115093	3	40	f	\N	\N
e9147e9d-670c-4c81-9756-8751b2ee36e1	\N	auth-recovery-authn-code-form	5928e5d4-c400-4150-9107-da98acace8cf	c44f6235-0962-46d7-8869-7a5998115093	3	50	f	\N	\N
1a67bbe3-3194-4531-b802-4fd563f9eecf	\N	\N	5928e5d4-c400-4150-9107-da98acace8cf	e6b61eb8-2edd-45b8-b81a-23cd657e397d	1	60	t	98512b09-7663-4e66-b158-5e7245e6e198	\N
75c39b8c-c36f-4a7b-8ff2-459d301c4a87	\N	conditional-user-configured	5928e5d4-c400-4150-9107-da98acace8cf	98512b09-7663-4e66-b158-5e7245e6e198	0	10	f	\N	\N
f7878ba5-42b8-49e7-a56b-7ff59d0add13	\N	idp-add-organization-member	5928e5d4-c400-4150-9107-da98acace8cf	98512b09-7663-4e66-b158-5e7245e6e198	0	20	f	\N	\N
bb8bd84d-0f22-4998-9c48-88f58237fa8f	\N	http-basic-authenticator	5928e5d4-c400-4150-9107-da98acace8cf	d071b90f-a565-4d5d-8bcf-cd340fcfa866	0	10	f	\N	\N
26eeb363-92ee-4a51-9c45-41189f6d630a	\N	docker-http-basic-authenticator	5928e5d4-c400-4150-9107-da98acace8cf	b13d0e4c-0ae6-42ae-b0f3-9b10c34b2062	0	10	f	\N	\N
\.


--
-- Data for Name: authentication_flow; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.authentication_flow (id, alias, description, realm_id, provider_id, top_level, built_in) FROM stdin;
11c99cf1-51bb-4b35-936e-08120938e064	browser	Browser based authentication	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	t	t
d2f9f9f4-ee4a-4739-821c-8b560e537677	forms	Username, password, otp and other auth forms.	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	f	t
f25cbf37-bf78-4838-8d34-5f7ff86d83e7	Browser - Conditional 2FA	Flow to determine if any 2FA is required for the authentication	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	f	t
acf00bd3-ff09-4e6a-96af-3fbe054f6b21	direct grant	OpenID Connect Resource Owner Grant	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	t	t
cfedfa8e-98a5-4fc7-941a-f5dd7214efa5	Direct Grant - Conditional OTP	Flow to determine if the OTP is required for the authentication	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	f	t
7badefb3-ac43-43ba-8028-608c6f6438e2	registration	Registration flow	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	t	t
ecb0ddb9-a3d7-47f2-904f-270d05d6c73c	registration form	Registration form	331e6113-4db4-4433-997e-09db1350e12a	form-flow	f	t
e4ba5024-be4b-49f9-9be8-7de0ec713ca3	reset credentials	Reset credentials for a user if they forgot their password or something	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	t	t
5ef484be-8ef0-4657-a527-dee1a41b47ab	Reset - Conditional OTP	Flow to determine if the OTP should be reset or not. Set to REQUIRED to force.	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	f	t
d0aca77b-fb6b-494c-8602-c984ef78120d	clients	Base authentication for clients	331e6113-4db4-4433-997e-09db1350e12a	client-flow	t	t
306af93f-cb5f-49a9-9533-947f7df994b3	first broker login	Actions taken after first broker login with identity provider account, which is not yet linked to any Keycloak account	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	t	t
5d6e3938-655c-41cb-bb90-dbf5ccda4bbe	User creation or linking	Flow for the existing/non-existing user alternatives	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	f	t
352bf0c2-8759-419a-a402-e2b123a077cc	Handle Existing Account	Handle what to do if there is existing account with same email/username like authenticated identity provider	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	f	t
95072ae6-e5b9-4bf9-8d26-343a82f2f097	Account verification options	Method with which to verify the existing account	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	f	t
59c3ee72-e38c-4a2c-ba36-a22e951b7c7c	Verify Existing Account by Re-authentication	Reauthentication of existing account	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	f	t
d7ea1bbd-35bc-4b2b-ab0d-4e79f73fb78a	First broker login - Conditional 2FA	Flow to determine if any 2FA is required for the authentication	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	f	t
723ded02-5b41-4241-bad8-e85071c97b03	saml ecp	SAML ECP Profile Authentication Flow	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	t	t
193dd51a-cea0-4619-ade0-2780e330204a	docker auth	Used by Docker clients to authenticate against the IDP	331e6113-4db4-4433-997e-09db1350e12a	basic-flow	t	t
509d7aad-da1f-4abd-aab1-1a7478101578	browser	Browser based authentication	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	t	t
badcebd3-fceb-44ca-875a-00b3518be892	forms	Username, password, otp and other auth forms.	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	f	t
ed515fe6-8a07-46a7-b361-1e84dcf79915	Browser - Conditional 2FA	Flow to determine if any 2FA is required for the authentication	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	f	t
0118d63c-22f2-4e1f-949b-e8dfd166ea80	Organization	\N	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	f	t
ea45eba4-61b1-4b17-bae7-a9439f8f101b	Browser - Conditional Organization	Flow to determine if the organization identity-first login is to be used	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	f	t
34d95689-1631-4af2-b2f3-82c538c316f2	direct grant	OpenID Connect Resource Owner Grant	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	t	t
1bcb4447-0741-4aaa-9c1f-1011511c52bc	Direct Grant - Conditional OTP	Flow to determine if the OTP is required for the authentication	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	f	t
d0baeced-93df-464d-b388-18f8b2629324	registration	Registration flow	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	t	t
a15100aa-9bd7-4a3d-b66d-e5b6d074f500	registration form	Registration form	5928e5d4-c400-4150-9107-da98acace8cf	form-flow	f	t
c1cc7640-d4e9-48e7-b062-aced0771c2b4	reset credentials	Reset credentials for a user if they forgot their password or something	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	t	t
6a7ac786-007a-44dc-91f2-45b01f233881	Reset - Conditional OTP	Flow to determine if the OTP should be reset or not. Set to REQUIRED to force.	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	f	t
9770201c-6ffe-4089-adab-d16b13fdcfd6	clients	Base authentication for clients	5928e5d4-c400-4150-9107-da98acace8cf	client-flow	t	t
e6b61eb8-2edd-45b8-b81a-23cd657e397d	first broker login	Actions taken after first broker login with identity provider account, which is not yet linked to any Keycloak account	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	t	t
15b3a4b0-6dc6-4349-a977-b96bb61d9d10	User creation or linking	Flow for the existing/non-existing user alternatives	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	f	t
a8d0064b-ed5c-45ea-adcd-8887a460cf73	Handle Existing Account	Handle what to do if there is existing account with same email/username like authenticated identity provider	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	f	t
dcb3c4c0-06f8-41e1-bd8b-e65e83e13495	Account verification options	Method with which to verify the existing account	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	f	t
10b3c034-1d3e-4a1a-9da1-16c343b9f376	Verify Existing Account by Re-authentication	Reauthentication of existing account	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	f	t
c44f6235-0962-46d7-8869-7a5998115093	First broker login - Conditional 2FA	Flow to determine if any 2FA is required for the authentication	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	f	t
98512b09-7663-4e66-b158-5e7245e6e198	First Broker Login - Conditional Organization	Flow to determine if the authenticator that adds organization members is to be used	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	f	t
d071b90f-a565-4d5d-8bcf-cd340fcfa866	saml ecp	SAML ECP Profile Authentication Flow	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	t	t
b13d0e4c-0ae6-42ae-b0f3-9b10c34b2062	docker auth	Used by Docker clients to authenticate against the IDP	5928e5d4-c400-4150-9107-da98acace8cf	basic-flow	t	t
\.


--
-- Data for Name: authenticator_config; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.authenticator_config (id, alias, realm_id) FROM stdin;
d0ddc5f6-8e08-4d97-b81c-347433c9cc04	browser-conditional-credential	331e6113-4db4-4433-997e-09db1350e12a
4d32c0d0-84c2-4ff9-a0c1-dafc3e01a520	review profile config	331e6113-4db4-4433-997e-09db1350e12a
b48c7109-adec-4a69-a813-27b2a2da237e	create unique user config	331e6113-4db4-4433-997e-09db1350e12a
1ef3b979-a1e5-4291-844c-a8350c748ba2	first-broker-login-conditional-credential	331e6113-4db4-4433-997e-09db1350e12a
132f8184-413f-4cbd-a095-a3c536f4080f	browser-conditional-credential	5928e5d4-c400-4150-9107-da98acace8cf
85424540-624c-4c3a-bfa6-3e6d8a99889a	review profile config	5928e5d4-c400-4150-9107-da98acace8cf
a2a51cb2-6135-41f4-a081-254ad98d2300	create unique user config	5928e5d4-c400-4150-9107-da98acace8cf
f3625cae-e260-4a03-8674-419c79211ca1	first-broker-login-conditional-credential	5928e5d4-c400-4150-9107-da98acace8cf
\.


--
-- Data for Name: authenticator_config_entry; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.authenticator_config_entry (authenticator_id, value, name) FROM stdin;
1ef3b979-a1e5-4291-844c-a8350c748ba2	webauthn-passwordless	credentials
4d32c0d0-84c2-4ff9-a0c1-dafc3e01a520	missing	update.profile.on.first.login
b48c7109-adec-4a69-a813-27b2a2da237e	false	require.password.update.after.registration
d0ddc5f6-8e08-4d97-b81c-347433c9cc04	webauthn-passwordless	credentials
132f8184-413f-4cbd-a095-a3c536f4080f	webauthn-passwordless	credentials
85424540-624c-4c3a-bfa6-3e6d8a99889a	missing	update.profile.on.first.login
a2a51cb2-6135-41f4-a081-254ad98d2300	false	require.password.update.after.registration
f3625cae-e260-4a03-8674-419c79211ca1	webauthn-passwordless	credentials
\.


--
-- Data for Name: broker_link; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.broker_link (identity_provider, storage_provider_id, realm_id, broker_user_id, broker_username, token, user_id) FROM stdin;
\.


--
-- Data for Name: client; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.client (id, enabled, full_scope_allowed, client_id, not_before, public_client, secret, base_url, bearer_only, management_url, surrogate_auth_required, realm_id, protocol, node_rereg_timeout, frontchannel_logout, consent_required, name, service_accounts_enabled, client_authenticator_type, root_url, description, registration_token, standard_flow_enabled, implicit_flow_enabled, direct_access_grants_enabled, always_display_in_console, created_timestamp, last_modified_timestamp) FROM stdin;
4caeb1d0-bc9d-4239-a764-0237ee150cec	t	f	master-realm	0	f	\N	\N	t	\N	f	331e6113-4db4-4433-997e-09db1350e12a	\N	0	f	f	master Realm	f	client-secret	\N	\N	\N	t	f	f	f	1792569171929	1792569171948
02c5d277-7643-45c6-a008-1bba899b38ef	t	f	account	0	t	\N	/realms/master/account/	f	\N	f	331e6113-4db4-4433-997e-09db1350e12a	openid-connect	0	f	f	${client_account}	f	client-secret	${authBaseUrl}	\N	\N	t	f	f	f	1792569172759	1792569172848
00b14034-0863-4908-85f7-81849f8af952	t	f	account-console	0	t	\N	/realms/master/account/	f	\N	f	331e6113-4db4-4433-997e-09db1350e12a	openid-connect	0	f	f	${client_account-console}	f	client-secret	${authBaseUrl}	\N	\N	t	f	f	f	1792569173084	1792569173155
eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	t	f	broker	0	f	\N	\N	t	\N	f	331e6113-4db4-4433-997e-09db1350e12a	openid-connect	0	f	f	${client_broker}	f	client-secret	\N	\N	\N	t	f	f	f	1792569173235	1792569173318
a7ac4e8e-3117-44a8-95b0-f02c71ded253	t	t	security-admin-console	0	t	\N	/admin/master/console/	f	\N	f	331e6113-4db4-4433-997e-09db1350e12a	openid-connect	0	f	f	${client_security-admin-console}	f	client-secret	${authAdminUrl}	\N	\N	t	f	f	f	1792569173374	1792569173457
38a5a9d1-96f6-4dc3-9e4a-86eef2b996e6	t	t	admin-cli	0	t	\N	\N	f	\N	f	331e6113-4db4-4433-997e-09db1350e12a	openid-connect	0	f	f	${client_admin-cli}	f	client-secret	\N	\N	\N	f	f	t	f	1792569173520	1792569173596
db6561a3-eade-43c8-aff5-28c54ee54e19	t	f	erp-realm-realm	0	f	\N	\N	t	\N	f	331e6113-4db4-4433-997e-09db1350e12a	\N	0	f	f	erp-realm Realm	f	client-secret	\N	\N	\N	t	f	f	f	1792569668644	1792569668646
8b21bcbe-534e-4196-a20e-4f2592399d8c	t	f	realm-management	0	f	\N	\N	t	\N	f	5928e5d4-c400-4150-9107-da98acace8cf	openid-connect	0	f	f	${client_realm-management}	f	client-secret	\N	\N	\N	t	f	f	f	1792569668944	1792569668964
5acab47a-ebce-406b-aaea-a826b37a7a67	t	f	account	0	t	\N	/realms/erp-realm/account/	f	\N	f	5928e5d4-c400-4150-9107-da98acace8cf	openid-connect	0	f	f	${client_account}	f	client-secret	${authBaseUrl}	\N	\N	t	f	f	f	1792569669249	1792569669272
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	t	f	account-console	0	t	\N	/realms/erp-realm/account/	f	\N	f	5928e5d4-c400-4150-9107-da98acace8cf	openid-connect	0	f	f	${client_account-console}	f	client-secret	${authBaseUrl}	\N	\N	t	f	f	f	1792569669358	1792569669376
eea055c7-237a-45c7-aa48-0f8c0c89f9ba	t	f	broker	0	f	\N	\N	t	\N	f	5928e5d4-c400-4150-9107-da98acace8cf	openid-connect	0	f	f	${client_broker}	f	client-secret	\N	\N	\N	t	f	f	f	1792569669460	1792569669483
02921f33-7315-4da6-aa49-bb63211e78df	t	t	security-admin-console	0	t	\N	/admin/erp-realm/console/	f	\N	f	5928e5d4-c400-4150-9107-da98acace8cf	openid-connect	0	f	f	${client_security-admin-console}	f	client-secret	${authAdminUrl}	\N	\N	t	f	f	f	1792569669497	1792569669523
37f62172-833c-45e1-b895-66d79a12724f	t	t	admin-cli	0	t	\N	\N	f	\N	f	5928e5d4-c400-4150-9107-da98acace8cf	openid-connect	0	f	f	${client_admin-cli}	f	client-secret	\N	\N	\N	f	f	t	f	1792569669537	1792569669559
9944fc9f-2d6f-4ae5-bb98-75124c770501	t	t	erp-client	0	t	\N		f		f	5928e5d4-c400-4150-9107-da98acace8cf	openid-connect	-1	t	f		f	client-secret			\N	t	f	t	f	1792569930162	1792648428851
\.


--
-- Data for Name: client_attributes; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.client_attributes (client_id, name, value) FROM stdin;
02c5d277-7643-45c6-a008-1bba899b38ef	post.logout.redirect.uris	+
00b14034-0863-4908-85f7-81849f8af952	post.logout.redirect.uris	+
00b14034-0863-4908-85f7-81849f8af952	pkce.code.challenge.method	S256
a7ac4e8e-3117-44a8-95b0-f02c71ded253	post.logout.redirect.uris	+
a7ac4e8e-3117-44a8-95b0-f02c71ded253	pkce.code.challenge.method	S256
a7ac4e8e-3117-44a8-95b0-f02c71ded253	client.use.lightweight.access.token.enabled	true
38a5a9d1-96f6-4dc3-9e4a-86eef2b996e6	client.use.lightweight.access.token.enabled	true
5acab47a-ebce-406b-aaea-a826b37a7a67	post.logout.redirect.uris	+
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	post.logout.redirect.uris	+
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	pkce.code.challenge.method	S256
02921f33-7315-4da6-aa49-bb63211e78df	post.logout.redirect.uris	+
02921f33-7315-4da6-aa49-bb63211e78df	pkce.code.challenge.method	S256
02921f33-7315-4da6-aa49-bb63211e78df	client.use.lightweight.access.token.enabled	true
37f62172-833c-45e1-b895-66d79a12724f	client.use.lightweight.access.token.enabled	true
9944fc9f-2d6f-4ae5-bb98-75124c770501	client.secret.creation.time	1792569930
9944fc9f-2d6f-4ae5-bb98-75124c770501	standard.token.exchange.enabled	false
9944fc9f-2d6f-4ae5-bb98-75124c770501	oauth2.jwt.authorization.grant.enabled	false
9944fc9f-2d6f-4ae5-bb98-75124c770501	oauth2.device.authorization.grant.enabled	false
9944fc9f-2d6f-4ae5-bb98-75124c770501	oidc.ciba.grant.enabled	false
9944fc9f-2d6f-4ae5-bb98-75124c770501	dpop.bound.access.tokens	false
9944fc9f-2d6f-4ae5-bb98-75124c770501	backchannel.logout.session.required	true
9944fc9f-2d6f-4ae5-bb98-75124c770501	backchannel.logout.revoke.offline.tokens	false
9944fc9f-2d6f-4ae5-bb98-75124c770501	display.on.consent.screen	false
9944fc9f-2d6f-4ae5-bb98-75124c770501	frontchannel.logout.session.required	true
9944fc9f-2d6f-4ae5-bb98-75124c770501	logout.confirmation.enabled	false
9944fc9f-2d6f-4ae5-bb98-75124c770501	post.logout.redirect.uris	http://localhost:*
9944fc9f-2d6f-4ae5-bb98-75124c770501	ssf.enabled	false
\.


--
-- Data for Name: client_auth_flow_bindings; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.client_auth_flow_bindings (client_id, flow_id, binding_name) FROM stdin;
\.


--
-- Data for Name: client_initial_access; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.client_initial_access (id, realm_id, "timestamp", expiration, count, remaining_count) FROM stdin;
\.


--
-- Data for Name: client_node_registrations; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.client_node_registrations (client_id, value, name) FROM stdin;
\.


--
-- Data for Name: client_scope; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.client_scope (id, name, realm_id, description, protocol) FROM stdin;
b386def2-101f-42cc-af67-160605b0c1b2	offline_access	331e6113-4db4-4433-997e-09db1350e12a	OpenID Connect built-in scope: offline_access	openid-connect
e405615b-e22c-44eb-80ae-84dff928cd7f	role_list	331e6113-4db4-4433-997e-09db1350e12a	SAML role list	saml
be4015dd-3b59-4cfa-a3e4-9c0112a90d5d	saml_organization	331e6113-4db4-4433-997e-09db1350e12a	Organization Membership	saml
549bfb16-8cc0-4634-ae5b-f4073270b3e4	AuthnContextClassRef	331e6113-4db4-4433-997e-09db1350e12a	AuthnContextClassRef Level of Authentiation	saml
b448fe6b-e8e6-4adc-9ff7-45628fcb4560	profile	331e6113-4db4-4433-997e-09db1350e12a	OpenID Connect built-in scope: profile	openid-connect
f09699e1-d95e-4dae-8187-1b6380b82a40	email	331e6113-4db4-4433-997e-09db1350e12a	OpenID Connect built-in scope: email	openid-connect
ee3ade41-39d1-441d-9922-f7dc73cd8f24	address	331e6113-4db4-4433-997e-09db1350e12a	OpenID Connect built-in scope: address	openid-connect
2f0d6ac3-76de-4d40-9825-5db7a96054a2	phone	331e6113-4db4-4433-997e-09db1350e12a	OpenID Connect built-in scope: phone	openid-connect
335a2bcc-3f75-4032-bd25-d368c817655d	roles	331e6113-4db4-4433-997e-09db1350e12a	OpenID Connect scope for add user roles to the access token	openid-connect
31bb7ee4-e3fa-4a1b-a242-eb86a98ea2c8	web-origins	331e6113-4db4-4433-997e-09db1350e12a	OpenID Connect scope for add allowed web origins to the access token	openid-connect
6977c07d-a0b9-4661-9ab0-8b5dcc5df3ae	microprofile-jwt	331e6113-4db4-4433-997e-09db1350e12a	Microprofile - JWT built-in scope	openid-connect
ec99790c-0896-4e6b-962a-a4295e6ce499	acr	331e6113-4db4-4433-997e-09db1350e12a	OpenID Connect scope for add acr (authentication context class reference) to the token	openid-connect
468ad7f4-9f9f-4b4b-be02-4305be58e7dd	basic	331e6113-4db4-4433-997e-09db1350e12a	OpenID Connect scope for add all basic claims to the token	openid-connect
ec60fad4-9c97-450b-bb63-73bfdd9a8b0f	service_account	331e6113-4db4-4433-997e-09db1350e12a	Specific scope for a client enabled for service accounts	openid-connect
bb5bb9a1-ba1e-432a-a857-c6c0291b2c54	organization	331e6113-4db4-4433-997e-09db1350e12a	Additional claims about the organization a subject belongs to	openid-connect
f9106c30-ad3c-448d-99bb-fc6fa0353cc7	offline_access	5928e5d4-c400-4150-9107-da98acace8cf	OpenID Connect built-in scope: offline_access	openid-connect
e134ec31-7d01-464d-b16b-4a71984873a1	role_list	5928e5d4-c400-4150-9107-da98acace8cf	SAML role list	saml
5dab62a2-1f8c-4803-8c32-44158a24ab0a	saml_organization	5928e5d4-c400-4150-9107-da98acace8cf	Organization Membership	saml
e8a13582-4580-44e2-ab5c-f8b0a8ce4b52	AuthnContextClassRef	5928e5d4-c400-4150-9107-da98acace8cf	AuthnContextClassRef Level of Authentiation	saml
ffb9f715-58c7-4afe-89ed-98862944e1f5	profile	5928e5d4-c400-4150-9107-da98acace8cf	OpenID Connect built-in scope: profile	openid-connect
e8ef943d-eef2-4d47-9710-d7105d4a9e80	email	5928e5d4-c400-4150-9107-da98acace8cf	OpenID Connect built-in scope: email	openid-connect
32c939de-30ec-4a62-96c0-00847c91aacf	address	5928e5d4-c400-4150-9107-da98acace8cf	OpenID Connect built-in scope: address	openid-connect
6b2b117d-a23d-4844-9cbe-821f02964cf7	phone	5928e5d4-c400-4150-9107-da98acace8cf	OpenID Connect built-in scope: phone	openid-connect
5ebfdbc1-e201-418c-b5af-8e28d36bf4f8	roles	5928e5d4-c400-4150-9107-da98acace8cf	OpenID Connect scope for add user roles to the access token	openid-connect
e9472182-f327-442e-9c0b-4c7745ea2ae8	web-origins	5928e5d4-c400-4150-9107-da98acace8cf	OpenID Connect scope for add allowed web origins to the access token	openid-connect
bd194148-647b-4081-bb24-5c760c78d0e2	microprofile-jwt	5928e5d4-c400-4150-9107-da98acace8cf	Microprofile - JWT built-in scope	openid-connect
53e24107-4a5b-4e1b-9c18-478e75199b39	acr	5928e5d4-c400-4150-9107-da98acace8cf	OpenID Connect scope for add acr (authentication context class reference) to the token	openid-connect
c0da43db-fc02-412e-829f-3d06eb946b76	basic	5928e5d4-c400-4150-9107-da98acace8cf	OpenID Connect scope for add all basic claims to the token	openid-connect
045fcd1d-8a27-47c2-812d-5e4b2cc0b483	service_account	5928e5d4-c400-4150-9107-da98acace8cf	Specific scope for a client enabled for service accounts	openid-connect
cc70a7eb-bb51-4244-966d-e495cfe0f2bd	organization	5928e5d4-c400-4150-9107-da98acace8cf	Additional claims about the organization a subject belongs to	openid-connect
\.


--
-- Data for Name: client_scope_attributes; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.client_scope_attributes (scope_id, value, name) FROM stdin;
b386def2-101f-42cc-af67-160605b0c1b2	true	display.on.consent.screen
b386def2-101f-42cc-af67-160605b0c1b2	${offlineAccessScopeConsentText}	consent.screen.text
e405615b-e22c-44eb-80ae-84dff928cd7f	true	display.on.consent.screen
e405615b-e22c-44eb-80ae-84dff928cd7f	${samlRoleListScopeConsentText}	consent.screen.text
be4015dd-3b59-4cfa-a3e4-9c0112a90d5d	false	display.on.consent.screen
b448fe6b-e8e6-4adc-9ff7-45628fcb4560	true	display.on.consent.screen
b448fe6b-e8e6-4adc-9ff7-45628fcb4560	${profileScopeConsentText}	consent.screen.text
b448fe6b-e8e6-4adc-9ff7-45628fcb4560	true	include.in.token.scope
f09699e1-d95e-4dae-8187-1b6380b82a40	true	display.on.consent.screen
f09699e1-d95e-4dae-8187-1b6380b82a40	${emailScopeConsentText}	consent.screen.text
f09699e1-d95e-4dae-8187-1b6380b82a40	true	include.in.token.scope
ee3ade41-39d1-441d-9922-f7dc73cd8f24	true	display.on.consent.screen
ee3ade41-39d1-441d-9922-f7dc73cd8f24	${addressScopeConsentText}	consent.screen.text
ee3ade41-39d1-441d-9922-f7dc73cd8f24	true	include.in.token.scope
2f0d6ac3-76de-4d40-9825-5db7a96054a2	true	display.on.consent.screen
2f0d6ac3-76de-4d40-9825-5db7a96054a2	${phoneScopeConsentText}	consent.screen.text
2f0d6ac3-76de-4d40-9825-5db7a96054a2	true	include.in.token.scope
335a2bcc-3f75-4032-bd25-d368c817655d	true	display.on.consent.screen
335a2bcc-3f75-4032-bd25-d368c817655d	${rolesScopeConsentText}	consent.screen.text
335a2bcc-3f75-4032-bd25-d368c817655d	false	include.in.token.scope
31bb7ee4-e3fa-4a1b-a242-eb86a98ea2c8	false	display.on.consent.screen
31bb7ee4-e3fa-4a1b-a242-eb86a98ea2c8		consent.screen.text
31bb7ee4-e3fa-4a1b-a242-eb86a98ea2c8	false	include.in.token.scope
6977c07d-a0b9-4661-9ab0-8b5dcc5df3ae	false	display.on.consent.screen
6977c07d-a0b9-4661-9ab0-8b5dcc5df3ae	true	include.in.token.scope
ec99790c-0896-4e6b-962a-a4295e6ce499	false	display.on.consent.screen
ec99790c-0896-4e6b-962a-a4295e6ce499	false	include.in.token.scope
468ad7f4-9f9f-4b4b-be02-4305be58e7dd	false	display.on.consent.screen
468ad7f4-9f9f-4b4b-be02-4305be58e7dd	false	include.in.token.scope
ec60fad4-9c97-450b-bb63-73bfdd9a8b0f	false	display.on.consent.screen
ec60fad4-9c97-450b-bb63-73bfdd9a8b0f	false	include.in.token.scope
bb5bb9a1-ba1e-432a-a857-c6c0291b2c54	true	display.on.consent.screen
bb5bb9a1-ba1e-432a-a857-c6c0291b2c54	${organizationScopeConsentText}	consent.screen.text
bb5bb9a1-ba1e-432a-a857-c6c0291b2c54	true	include.in.token.scope
f9106c30-ad3c-448d-99bb-fc6fa0353cc7	true	display.on.consent.screen
f9106c30-ad3c-448d-99bb-fc6fa0353cc7	${offlineAccessScopeConsentText}	consent.screen.text
e134ec31-7d01-464d-b16b-4a71984873a1	true	display.on.consent.screen
e134ec31-7d01-464d-b16b-4a71984873a1	${samlRoleListScopeConsentText}	consent.screen.text
5dab62a2-1f8c-4803-8c32-44158a24ab0a	false	display.on.consent.screen
ffb9f715-58c7-4afe-89ed-98862944e1f5	true	display.on.consent.screen
ffb9f715-58c7-4afe-89ed-98862944e1f5	${profileScopeConsentText}	consent.screen.text
ffb9f715-58c7-4afe-89ed-98862944e1f5	true	include.in.token.scope
e8ef943d-eef2-4d47-9710-d7105d4a9e80	true	display.on.consent.screen
e8ef943d-eef2-4d47-9710-d7105d4a9e80	${emailScopeConsentText}	consent.screen.text
e8ef943d-eef2-4d47-9710-d7105d4a9e80	true	include.in.token.scope
32c939de-30ec-4a62-96c0-00847c91aacf	true	display.on.consent.screen
32c939de-30ec-4a62-96c0-00847c91aacf	${addressScopeConsentText}	consent.screen.text
32c939de-30ec-4a62-96c0-00847c91aacf	true	include.in.token.scope
6b2b117d-a23d-4844-9cbe-821f02964cf7	true	display.on.consent.screen
6b2b117d-a23d-4844-9cbe-821f02964cf7	${phoneScopeConsentText}	consent.screen.text
6b2b117d-a23d-4844-9cbe-821f02964cf7	true	include.in.token.scope
5ebfdbc1-e201-418c-b5af-8e28d36bf4f8	true	display.on.consent.screen
5ebfdbc1-e201-418c-b5af-8e28d36bf4f8	${rolesScopeConsentText}	consent.screen.text
5ebfdbc1-e201-418c-b5af-8e28d36bf4f8	false	include.in.token.scope
e9472182-f327-442e-9c0b-4c7745ea2ae8	false	display.on.consent.screen
e9472182-f327-442e-9c0b-4c7745ea2ae8		consent.screen.text
e9472182-f327-442e-9c0b-4c7745ea2ae8	false	include.in.token.scope
bd194148-647b-4081-bb24-5c760c78d0e2	false	display.on.consent.screen
bd194148-647b-4081-bb24-5c760c78d0e2	true	include.in.token.scope
53e24107-4a5b-4e1b-9c18-478e75199b39	false	display.on.consent.screen
53e24107-4a5b-4e1b-9c18-478e75199b39	false	include.in.token.scope
c0da43db-fc02-412e-829f-3d06eb946b76	false	display.on.consent.screen
c0da43db-fc02-412e-829f-3d06eb946b76	false	include.in.token.scope
045fcd1d-8a27-47c2-812d-5e4b2cc0b483	false	display.on.consent.screen
045fcd1d-8a27-47c2-812d-5e4b2cc0b483	false	include.in.token.scope
cc70a7eb-bb51-4244-966d-e495cfe0f2bd	true	display.on.consent.screen
cc70a7eb-bb51-4244-966d-e495cfe0f2bd	${organizationScopeConsentText}	consent.screen.text
cc70a7eb-bb51-4244-966d-e495cfe0f2bd	true	include.in.token.scope
\.


--
-- Data for Name: client_scope_client; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.client_scope_client (client_id, scope_id, default_scope) FROM stdin;
02c5d277-7643-45c6-a008-1bba899b38ef	31bb7ee4-e3fa-4a1b-a242-eb86a98ea2c8	t
02c5d277-7643-45c6-a008-1bba899b38ef	468ad7f4-9f9f-4b4b-be02-4305be58e7dd	t
02c5d277-7643-45c6-a008-1bba899b38ef	f09699e1-d95e-4dae-8187-1b6380b82a40	t
02c5d277-7643-45c6-a008-1bba899b38ef	335a2bcc-3f75-4032-bd25-d368c817655d	t
02c5d277-7643-45c6-a008-1bba899b38ef	ec99790c-0896-4e6b-962a-a4295e6ce499	t
02c5d277-7643-45c6-a008-1bba899b38ef	b448fe6b-e8e6-4adc-9ff7-45628fcb4560	t
02c5d277-7643-45c6-a008-1bba899b38ef	6977c07d-a0b9-4661-9ab0-8b5dcc5df3ae	f
02c5d277-7643-45c6-a008-1bba899b38ef	2f0d6ac3-76de-4d40-9825-5db7a96054a2	f
02c5d277-7643-45c6-a008-1bba899b38ef	bb5bb9a1-ba1e-432a-a857-c6c0291b2c54	f
02c5d277-7643-45c6-a008-1bba899b38ef	ee3ade41-39d1-441d-9922-f7dc73cd8f24	f
02c5d277-7643-45c6-a008-1bba899b38ef	b386def2-101f-42cc-af67-160605b0c1b2	f
00b14034-0863-4908-85f7-81849f8af952	31bb7ee4-e3fa-4a1b-a242-eb86a98ea2c8	t
00b14034-0863-4908-85f7-81849f8af952	468ad7f4-9f9f-4b4b-be02-4305be58e7dd	t
00b14034-0863-4908-85f7-81849f8af952	f09699e1-d95e-4dae-8187-1b6380b82a40	t
00b14034-0863-4908-85f7-81849f8af952	335a2bcc-3f75-4032-bd25-d368c817655d	t
00b14034-0863-4908-85f7-81849f8af952	ec99790c-0896-4e6b-962a-a4295e6ce499	t
00b14034-0863-4908-85f7-81849f8af952	b448fe6b-e8e6-4adc-9ff7-45628fcb4560	t
00b14034-0863-4908-85f7-81849f8af952	6977c07d-a0b9-4661-9ab0-8b5dcc5df3ae	f
00b14034-0863-4908-85f7-81849f8af952	2f0d6ac3-76de-4d40-9825-5db7a96054a2	f
00b14034-0863-4908-85f7-81849f8af952	bb5bb9a1-ba1e-432a-a857-c6c0291b2c54	f
00b14034-0863-4908-85f7-81849f8af952	ee3ade41-39d1-441d-9922-f7dc73cd8f24	f
00b14034-0863-4908-85f7-81849f8af952	b386def2-101f-42cc-af67-160605b0c1b2	f
38a5a9d1-96f6-4dc3-9e4a-86eef2b996e6	31bb7ee4-e3fa-4a1b-a242-eb86a98ea2c8	t
38a5a9d1-96f6-4dc3-9e4a-86eef2b996e6	468ad7f4-9f9f-4b4b-be02-4305be58e7dd	t
38a5a9d1-96f6-4dc3-9e4a-86eef2b996e6	f09699e1-d95e-4dae-8187-1b6380b82a40	t
38a5a9d1-96f6-4dc3-9e4a-86eef2b996e6	335a2bcc-3f75-4032-bd25-d368c817655d	t
38a5a9d1-96f6-4dc3-9e4a-86eef2b996e6	ec99790c-0896-4e6b-962a-a4295e6ce499	t
38a5a9d1-96f6-4dc3-9e4a-86eef2b996e6	b448fe6b-e8e6-4adc-9ff7-45628fcb4560	t
38a5a9d1-96f6-4dc3-9e4a-86eef2b996e6	6977c07d-a0b9-4661-9ab0-8b5dcc5df3ae	f
38a5a9d1-96f6-4dc3-9e4a-86eef2b996e6	2f0d6ac3-76de-4d40-9825-5db7a96054a2	f
38a5a9d1-96f6-4dc3-9e4a-86eef2b996e6	bb5bb9a1-ba1e-432a-a857-c6c0291b2c54	f
38a5a9d1-96f6-4dc3-9e4a-86eef2b996e6	ee3ade41-39d1-441d-9922-f7dc73cd8f24	f
38a5a9d1-96f6-4dc3-9e4a-86eef2b996e6	b386def2-101f-42cc-af67-160605b0c1b2	f
eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	31bb7ee4-e3fa-4a1b-a242-eb86a98ea2c8	t
eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	468ad7f4-9f9f-4b4b-be02-4305be58e7dd	t
eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	f09699e1-d95e-4dae-8187-1b6380b82a40	t
eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	335a2bcc-3f75-4032-bd25-d368c817655d	t
eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	ec99790c-0896-4e6b-962a-a4295e6ce499	t
eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	b448fe6b-e8e6-4adc-9ff7-45628fcb4560	t
eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	6977c07d-a0b9-4661-9ab0-8b5dcc5df3ae	f
eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	2f0d6ac3-76de-4d40-9825-5db7a96054a2	f
eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	bb5bb9a1-ba1e-432a-a857-c6c0291b2c54	f
eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	ee3ade41-39d1-441d-9922-f7dc73cd8f24	f
eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	b386def2-101f-42cc-af67-160605b0c1b2	f
4caeb1d0-bc9d-4239-a764-0237ee150cec	31bb7ee4-e3fa-4a1b-a242-eb86a98ea2c8	t
4caeb1d0-bc9d-4239-a764-0237ee150cec	468ad7f4-9f9f-4b4b-be02-4305be58e7dd	t
4caeb1d0-bc9d-4239-a764-0237ee150cec	f09699e1-d95e-4dae-8187-1b6380b82a40	t
4caeb1d0-bc9d-4239-a764-0237ee150cec	335a2bcc-3f75-4032-bd25-d368c817655d	t
4caeb1d0-bc9d-4239-a764-0237ee150cec	ec99790c-0896-4e6b-962a-a4295e6ce499	t
4caeb1d0-bc9d-4239-a764-0237ee150cec	b448fe6b-e8e6-4adc-9ff7-45628fcb4560	t
4caeb1d0-bc9d-4239-a764-0237ee150cec	6977c07d-a0b9-4661-9ab0-8b5dcc5df3ae	f
4caeb1d0-bc9d-4239-a764-0237ee150cec	2f0d6ac3-76de-4d40-9825-5db7a96054a2	f
4caeb1d0-bc9d-4239-a764-0237ee150cec	bb5bb9a1-ba1e-432a-a857-c6c0291b2c54	f
4caeb1d0-bc9d-4239-a764-0237ee150cec	ee3ade41-39d1-441d-9922-f7dc73cd8f24	f
4caeb1d0-bc9d-4239-a764-0237ee150cec	b386def2-101f-42cc-af67-160605b0c1b2	f
a7ac4e8e-3117-44a8-95b0-f02c71ded253	31bb7ee4-e3fa-4a1b-a242-eb86a98ea2c8	t
a7ac4e8e-3117-44a8-95b0-f02c71ded253	468ad7f4-9f9f-4b4b-be02-4305be58e7dd	t
a7ac4e8e-3117-44a8-95b0-f02c71ded253	f09699e1-d95e-4dae-8187-1b6380b82a40	t
a7ac4e8e-3117-44a8-95b0-f02c71ded253	335a2bcc-3f75-4032-bd25-d368c817655d	t
a7ac4e8e-3117-44a8-95b0-f02c71ded253	ec99790c-0896-4e6b-962a-a4295e6ce499	t
a7ac4e8e-3117-44a8-95b0-f02c71ded253	b448fe6b-e8e6-4adc-9ff7-45628fcb4560	t
a7ac4e8e-3117-44a8-95b0-f02c71ded253	6977c07d-a0b9-4661-9ab0-8b5dcc5df3ae	f
a7ac4e8e-3117-44a8-95b0-f02c71ded253	2f0d6ac3-76de-4d40-9825-5db7a96054a2	f
a7ac4e8e-3117-44a8-95b0-f02c71ded253	bb5bb9a1-ba1e-432a-a857-c6c0291b2c54	f
a7ac4e8e-3117-44a8-95b0-f02c71ded253	ee3ade41-39d1-441d-9922-f7dc73cd8f24	f
a7ac4e8e-3117-44a8-95b0-f02c71ded253	b386def2-101f-42cc-af67-160605b0c1b2	f
5acab47a-ebce-406b-aaea-a826b37a7a67	e8ef943d-eef2-4d47-9710-d7105d4a9e80	t
5acab47a-ebce-406b-aaea-a826b37a7a67	5ebfdbc1-e201-418c-b5af-8e28d36bf4f8	t
5acab47a-ebce-406b-aaea-a826b37a7a67	e9472182-f327-442e-9c0b-4c7745ea2ae8	t
5acab47a-ebce-406b-aaea-a826b37a7a67	c0da43db-fc02-412e-829f-3d06eb946b76	t
5acab47a-ebce-406b-aaea-a826b37a7a67	53e24107-4a5b-4e1b-9c18-478e75199b39	t
5acab47a-ebce-406b-aaea-a826b37a7a67	ffb9f715-58c7-4afe-89ed-98862944e1f5	t
5acab47a-ebce-406b-aaea-a826b37a7a67	bd194148-647b-4081-bb24-5c760c78d0e2	f
5acab47a-ebce-406b-aaea-a826b37a7a67	32c939de-30ec-4a62-96c0-00847c91aacf	f
5acab47a-ebce-406b-aaea-a826b37a7a67	6b2b117d-a23d-4844-9cbe-821f02964cf7	f
5acab47a-ebce-406b-aaea-a826b37a7a67	cc70a7eb-bb51-4244-966d-e495cfe0f2bd	f
5acab47a-ebce-406b-aaea-a826b37a7a67	f9106c30-ad3c-448d-99bb-fc6fa0353cc7	f
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	e8ef943d-eef2-4d47-9710-d7105d4a9e80	t
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	5ebfdbc1-e201-418c-b5af-8e28d36bf4f8	t
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	e9472182-f327-442e-9c0b-4c7745ea2ae8	t
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	c0da43db-fc02-412e-829f-3d06eb946b76	t
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	53e24107-4a5b-4e1b-9c18-478e75199b39	t
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	ffb9f715-58c7-4afe-89ed-98862944e1f5	t
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	bd194148-647b-4081-bb24-5c760c78d0e2	f
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	32c939de-30ec-4a62-96c0-00847c91aacf	f
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	6b2b117d-a23d-4844-9cbe-821f02964cf7	f
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	cc70a7eb-bb51-4244-966d-e495cfe0f2bd	f
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	f9106c30-ad3c-448d-99bb-fc6fa0353cc7	f
37f62172-833c-45e1-b895-66d79a12724f	e8ef943d-eef2-4d47-9710-d7105d4a9e80	t
37f62172-833c-45e1-b895-66d79a12724f	5ebfdbc1-e201-418c-b5af-8e28d36bf4f8	t
37f62172-833c-45e1-b895-66d79a12724f	e9472182-f327-442e-9c0b-4c7745ea2ae8	t
37f62172-833c-45e1-b895-66d79a12724f	c0da43db-fc02-412e-829f-3d06eb946b76	t
37f62172-833c-45e1-b895-66d79a12724f	53e24107-4a5b-4e1b-9c18-478e75199b39	t
37f62172-833c-45e1-b895-66d79a12724f	ffb9f715-58c7-4afe-89ed-98862944e1f5	t
37f62172-833c-45e1-b895-66d79a12724f	bd194148-647b-4081-bb24-5c760c78d0e2	f
37f62172-833c-45e1-b895-66d79a12724f	32c939de-30ec-4a62-96c0-00847c91aacf	f
37f62172-833c-45e1-b895-66d79a12724f	6b2b117d-a23d-4844-9cbe-821f02964cf7	f
37f62172-833c-45e1-b895-66d79a12724f	cc70a7eb-bb51-4244-966d-e495cfe0f2bd	f
37f62172-833c-45e1-b895-66d79a12724f	f9106c30-ad3c-448d-99bb-fc6fa0353cc7	f
eea055c7-237a-45c7-aa48-0f8c0c89f9ba	e8ef943d-eef2-4d47-9710-d7105d4a9e80	t
eea055c7-237a-45c7-aa48-0f8c0c89f9ba	5ebfdbc1-e201-418c-b5af-8e28d36bf4f8	t
eea055c7-237a-45c7-aa48-0f8c0c89f9ba	e9472182-f327-442e-9c0b-4c7745ea2ae8	t
eea055c7-237a-45c7-aa48-0f8c0c89f9ba	c0da43db-fc02-412e-829f-3d06eb946b76	t
eea055c7-237a-45c7-aa48-0f8c0c89f9ba	53e24107-4a5b-4e1b-9c18-478e75199b39	t
eea055c7-237a-45c7-aa48-0f8c0c89f9ba	ffb9f715-58c7-4afe-89ed-98862944e1f5	t
eea055c7-237a-45c7-aa48-0f8c0c89f9ba	bd194148-647b-4081-bb24-5c760c78d0e2	f
eea055c7-237a-45c7-aa48-0f8c0c89f9ba	32c939de-30ec-4a62-96c0-00847c91aacf	f
eea055c7-237a-45c7-aa48-0f8c0c89f9ba	6b2b117d-a23d-4844-9cbe-821f02964cf7	f
eea055c7-237a-45c7-aa48-0f8c0c89f9ba	cc70a7eb-bb51-4244-966d-e495cfe0f2bd	f
eea055c7-237a-45c7-aa48-0f8c0c89f9ba	f9106c30-ad3c-448d-99bb-fc6fa0353cc7	f
8b21bcbe-534e-4196-a20e-4f2592399d8c	e8ef943d-eef2-4d47-9710-d7105d4a9e80	t
8b21bcbe-534e-4196-a20e-4f2592399d8c	5ebfdbc1-e201-418c-b5af-8e28d36bf4f8	t
8b21bcbe-534e-4196-a20e-4f2592399d8c	e9472182-f327-442e-9c0b-4c7745ea2ae8	t
8b21bcbe-534e-4196-a20e-4f2592399d8c	c0da43db-fc02-412e-829f-3d06eb946b76	t
8b21bcbe-534e-4196-a20e-4f2592399d8c	53e24107-4a5b-4e1b-9c18-478e75199b39	t
8b21bcbe-534e-4196-a20e-4f2592399d8c	ffb9f715-58c7-4afe-89ed-98862944e1f5	t
8b21bcbe-534e-4196-a20e-4f2592399d8c	bd194148-647b-4081-bb24-5c760c78d0e2	f
8b21bcbe-534e-4196-a20e-4f2592399d8c	32c939de-30ec-4a62-96c0-00847c91aacf	f
8b21bcbe-534e-4196-a20e-4f2592399d8c	6b2b117d-a23d-4844-9cbe-821f02964cf7	f
8b21bcbe-534e-4196-a20e-4f2592399d8c	cc70a7eb-bb51-4244-966d-e495cfe0f2bd	f
8b21bcbe-534e-4196-a20e-4f2592399d8c	f9106c30-ad3c-448d-99bb-fc6fa0353cc7	f
02921f33-7315-4da6-aa49-bb63211e78df	e8ef943d-eef2-4d47-9710-d7105d4a9e80	t
02921f33-7315-4da6-aa49-bb63211e78df	5ebfdbc1-e201-418c-b5af-8e28d36bf4f8	t
02921f33-7315-4da6-aa49-bb63211e78df	e9472182-f327-442e-9c0b-4c7745ea2ae8	t
02921f33-7315-4da6-aa49-bb63211e78df	c0da43db-fc02-412e-829f-3d06eb946b76	t
02921f33-7315-4da6-aa49-bb63211e78df	53e24107-4a5b-4e1b-9c18-478e75199b39	t
02921f33-7315-4da6-aa49-bb63211e78df	ffb9f715-58c7-4afe-89ed-98862944e1f5	t
02921f33-7315-4da6-aa49-bb63211e78df	bd194148-647b-4081-bb24-5c760c78d0e2	f
02921f33-7315-4da6-aa49-bb63211e78df	32c939de-30ec-4a62-96c0-00847c91aacf	f
02921f33-7315-4da6-aa49-bb63211e78df	6b2b117d-a23d-4844-9cbe-821f02964cf7	f
02921f33-7315-4da6-aa49-bb63211e78df	cc70a7eb-bb51-4244-966d-e495cfe0f2bd	f
02921f33-7315-4da6-aa49-bb63211e78df	f9106c30-ad3c-448d-99bb-fc6fa0353cc7	f
9944fc9f-2d6f-4ae5-bb98-75124c770501	e8ef943d-eef2-4d47-9710-d7105d4a9e80	t
9944fc9f-2d6f-4ae5-bb98-75124c770501	5ebfdbc1-e201-418c-b5af-8e28d36bf4f8	t
9944fc9f-2d6f-4ae5-bb98-75124c770501	e9472182-f327-442e-9c0b-4c7745ea2ae8	t
9944fc9f-2d6f-4ae5-bb98-75124c770501	c0da43db-fc02-412e-829f-3d06eb946b76	t
9944fc9f-2d6f-4ae5-bb98-75124c770501	53e24107-4a5b-4e1b-9c18-478e75199b39	t
9944fc9f-2d6f-4ae5-bb98-75124c770501	ffb9f715-58c7-4afe-89ed-98862944e1f5	t
9944fc9f-2d6f-4ae5-bb98-75124c770501	bd194148-647b-4081-bb24-5c760c78d0e2	f
9944fc9f-2d6f-4ae5-bb98-75124c770501	32c939de-30ec-4a62-96c0-00847c91aacf	f
9944fc9f-2d6f-4ae5-bb98-75124c770501	6b2b117d-a23d-4844-9cbe-821f02964cf7	f
9944fc9f-2d6f-4ae5-bb98-75124c770501	cc70a7eb-bb51-4244-966d-e495cfe0f2bd	f
9944fc9f-2d6f-4ae5-bb98-75124c770501	f9106c30-ad3c-448d-99bb-fc6fa0353cc7	f
\.


--
-- Data for Name: client_scope_role_mapping; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.client_scope_role_mapping (scope_id, role_id) FROM stdin;
b386def2-101f-42cc-af67-160605b0c1b2	6c27b134-5f46-42ed-b519-f9c86c2f64bd
f9106c30-ad3c-448d-99bb-fc6fa0353cc7	c7fd25b0-998c-479f-9277-86d868a80406
\.


--
-- Data for Name: cluster_event; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.cluster_event (id, target_cluster, sender_cluster, event_data, created_at) FROM stdin;
\.


--
-- Data for Name: component; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.component (id, name, parent_id, provider_id, provider_type, realm_id, sub_type) FROM stdin;
6e8cf379-8545-4fa3-a9f0-f9c5881f6721	Trusted Hosts	331e6113-4db4-4433-997e-09db1350e12a	trusted-hosts	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	331e6113-4db4-4433-997e-09db1350e12a	anonymous
10f55056-8443-4d2f-b894-1d0ea1d1469d	Consent Required	331e6113-4db4-4433-997e-09db1350e12a	consent-required	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	331e6113-4db4-4433-997e-09db1350e12a	anonymous
622720a4-1bf2-4557-96f9-389390c2b454	Full Scope Disabled	331e6113-4db4-4433-997e-09db1350e12a	scope	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	331e6113-4db4-4433-997e-09db1350e12a	anonymous
3a572733-da64-4d88-9c60-a2ad8905d050	Max Clients Limit	331e6113-4db4-4433-997e-09db1350e12a	max-clients	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	331e6113-4db4-4433-997e-09db1350e12a	anonymous
d7aeb07d-92b9-4dc7-94a1-d538b7658489	Allowed Protocol Mapper Types	331e6113-4db4-4433-997e-09db1350e12a	allowed-protocol-mappers	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	331e6113-4db4-4433-997e-09db1350e12a	anonymous
d02719d2-4bb8-4ddd-abc0-591e6699d4af	Allowed Client Scopes	331e6113-4db4-4433-997e-09db1350e12a	allowed-client-templates	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	331e6113-4db4-4433-997e-09db1350e12a	anonymous
2c61ebfe-c023-4aa9-89f1-6eba2b8fa046	Allowed Registration Web Origins	331e6113-4db4-4433-997e-09db1350e12a	registration-web-origins	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	331e6113-4db4-4433-997e-09db1350e12a	anonymous
62d7dc96-16f0-4f35-b10d-6ebdf2b88cb9	Allowed Protocol Mapper Types	331e6113-4db4-4433-997e-09db1350e12a	allowed-protocol-mappers	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	331e6113-4db4-4433-997e-09db1350e12a	authenticated
0620f869-9291-456e-8709-5b29918c7c32	Allowed Client Scopes	331e6113-4db4-4433-997e-09db1350e12a	allowed-client-templates	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	331e6113-4db4-4433-997e-09db1350e12a	authenticated
fb7b7fbc-1cf2-46da-ad79-4f4402e04b0a	Allowed Registration Web Origins	331e6113-4db4-4433-997e-09db1350e12a	registration-web-origins	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	331e6113-4db4-4433-997e-09db1350e12a	authenticated
0b857494-29fa-4f46-80a7-647df6601411	rsa-generated	331e6113-4db4-4433-997e-09db1350e12a	rsa-generated	org.keycloak.keys.KeyProvider	331e6113-4db4-4433-997e-09db1350e12a	\N
8b88473a-e89d-4e1b-917f-d6d70770b723	rsa-enc-generated	331e6113-4db4-4433-997e-09db1350e12a	rsa-enc-generated	org.keycloak.keys.KeyProvider	331e6113-4db4-4433-997e-09db1350e12a	\N
0d07fdf1-d314-42d5-907e-42cb2bb0a799	hmac-generated-hs512	331e6113-4db4-4433-997e-09db1350e12a	hmac-generated	org.keycloak.keys.KeyProvider	331e6113-4db4-4433-997e-09db1350e12a	\N
955c0a2f-8893-43d4-8296-ba1e7057fb89	aes-generated	331e6113-4db4-4433-997e-09db1350e12a	aes-generated	org.keycloak.keys.KeyProvider	331e6113-4db4-4433-997e-09db1350e12a	\N
f7e87d11-592b-4636-bf51-c9b2284b12e8	\N	331e6113-4db4-4433-997e-09db1350e12a	declarative-user-profile	org.keycloak.userprofile.UserProfileProvider	331e6113-4db4-4433-997e-09db1350e12a	\N
9e333e7f-bd80-4991-929e-b23d0ed159dc	rsa-generated	5928e5d4-c400-4150-9107-da98acace8cf	rsa-generated	org.keycloak.keys.KeyProvider	5928e5d4-c400-4150-9107-da98acace8cf	\N
16787f78-eba0-4920-8162-cf35b5aba8bb	rsa-enc-generated	5928e5d4-c400-4150-9107-da98acace8cf	rsa-enc-generated	org.keycloak.keys.KeyProvider	5928e5d4-c400-4150-9107-da98acace8cf	\N
0104cc11-8104-4b83-afa8-bbfa7d3defc4	hmac-generated-hs512	5928e5d4-c400-4150-9107-da98acace8cf	hmac-generated	org.keycloak.keys.KeyProvider	5928e5d4-c400-4150-9107-da98acace8cf	\N
2900dcf3-420d-46c8-b634-651a8235eb92	aes-generated	5928e5d4-c400-4150-9107-da98acace8cf	aes-generated	org.keycloak.keys.KeyProvider	5928e5d4-c400-4150-9107-da98acace8cf	\N
b9295b49-8211-4e7b-9c8c-6f74d694868c	Trusted Hosts	5928e5d4-c400-4150-9107-da98acace8cf	trusted-hosts	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5928e5d4-c400-4150-9107-da98acace8cf	anonymous
9f8a5a89-888b-45d2-a5f7-7abf6dcfc2a8	Consent Required	5928e5d4-c400-4150-9107-da98acace8cf	consent-required	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5928e5d4-c400-4150-9107-da98acace8cf	anonymous
3494777a-7a48-454e-bae6-7387a5134940	Full Scope Disabled	5928e5d4-c400-4150-9107-da98acace8cf	scope	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5928e5d4-c400-4150-9107-da98acace8cf	anonymous
d0f65beb-46ee-4054-af72-0e191cbe50bf	Max Clients Limit	5928e5d4-c400-4150-9107-da98acace8cf	max-clients	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5928e5d4-c400-4150-9107-da98acace8cf	anonymous
982d05e0-abc1-43c2-a827-fe3d1f565665	Allowed Protocol Mapper Types	5928e5d4-c400-4150-9107-da98acace8cf	allowed-protocol-mappers	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5928e5d4-c400-4150-9107-da98acace8cf	anonymous
8c2f3f94-0d7a-4ca3-bae4-21e8e598abb8	Allowed Client Scopes	5928e5d4-c400-4150-9107-da98acace8cf	allowed-client-templates	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5928e5d4-c400-4150-9107-da98acace8cf	anonymous
d87b7558-fadb-4dff-83bd-4b2e429ccf67	Allowed Registration Web Origins	5928e5d4-c400-4150-9107-da98acace8cf	registration-web-origins	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5928e5d4-c400-4150-9107-da98acace8cf	anonymous
b9e00810-3d40-437a-8312-408fa0a6c744	Allowed Protocol Mapper Types	5928e5d4-c400-4150-9107-da98acace8cf	allowed-protocol-mappers	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5928e5d4-c400-4150-9107-da98acace8cf	authenticated
eefc06de-bb12-4e04-b5ca-e2801631d8a4	Allowed Client Scopes	5928e5d4-c400-4150-9107-da98acace8cf	allowed-client-templates	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5928e5d4-c400-4150-9107-da98acace8cf	authenticated
ceba0040-4064-4ab0-8507-c8e1b6d6492b	Allowed Registration Web Origins	5928e5d4-c400-4150-9107-da98acace8cf	registration-web-origins	org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy	5928e5d4-c400-4150-9107-da98acace8cf	authenticated
\.


--
-- Data for Name: component_config; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.component_config (id, component_id, name, value) FROM stdin;
574a4cf2-a1b0-4bbc-b1f8-9dc2648cd67f	6e8cf379-8545-4fa3-a9f0-f9c5881f6721	client-uris-must-match	true
686e55bd-0584-4af7-8bb9-6f02230a0934	6e8cf379-8545-4fa3-a9f0-f9c5881f6721	host-sending-registration-request-must-match	true
1b2f508b-fad3-4f9f-8319-e70b9e6e501c	0620f869-9291-456e-8709-5b29918c7c32	allow-default-scopes	true
2e4e2bc0-1708-4548-8c5c-b4811d7cb6e5	3a572733-da64-4d88-9c60-a2ad8905d050	max-clients	200
4f0d6cd1-a3ac-47e9-a434-6342899940c6	d02719d2-4bb8-4ddd-abc0-591e6699d4af	allow-default-scopes	true
9ced116f-4a9c-4ddc-8cae-69effd1b9d9c	d7aeb07d-92b9-4dc7-94a1-d538b7658489	allowed-protocol-mapper-types	oidc-address-mapper
00a0192c-81a7-4968-b1e8-463656953551	d7aeb07d-92b9-4dc7-94a1-d538b7658489	allowed-protocol-mapper-types	oidc-usermodel-property-mapper
08af447b-523e-4a2d-bc3a-243e95909b8d	d7aeb07d-92b9-4dc7-94a1-d538b7658489	allowed-protocol-mapper-types	oidc-usermodel-attribute-mapper
9cdda174-41a4-47b2-b9e3-41a87fe1538b	d7aeb07d-92b9-4dc7-94a1-d538b7658489	allowed-protocol-mapper-types	oidc-full-name-mapper
8f7ed469-ade9-4d3e-a6da-f737600ba389	d7aeb07d-92b9-4dc7-94a1-d538b7658489	allowed-protocol-mapper-types	saml-user-attribute-mapper
8f5718bf-e2fd-461c-ad33-c5c2b78cb092	d7aeb07d-92b9-4dc7-94a1-d538b7658489	allowed-protocol-mapper-types	saml-role-list-mapper
259e068e-ffb4-44ad-8a8d-335ad5b7b137	d7aeb07d-92b9-4dc7-94a1-d538b7658489	allowed-protocol-mapper-types	oidc-sha256-pairwise-sub-mapper
e31938a9-9c89-4346-ab2a-6ab3b514149b	d7aeb07d-92b9-4dc7-94a1-d538b7658489	allowed-protocol-mapper-types	saml-user-property-mapper
a55d9538-5364-4568-ac98-a3f1e9132797	62d7dc96-16f0-4f35-b10d-6ebdf2b88cb9	allowed-protocol-mapper-types	oidc-full-name-mapper
b8ab6c8c-da72-4263-ba32-325f5ee6f7a7	62d7dc96-16f0-4f35-b10d-6ebdf2b88cb9	allowed-protocol-mapper-types	oidc-sha256-pairwise-sub-mapper
286443ba-fe3a-4dfa-9b75-1a162222c3f4	62d7dc96-16f0-4f35-b10d-6ebdf2b88cb9	allowed-protocol-mapper-types	saml-role-list-mapper
82b949cd-0022-4452-95d3-6a7a99a3a269	62d7dc96-16f0-4f35-b10d-6ebdf2b88cb9	allowed-protocol-mapper-types	oidc-usermodel-attribute-mapper
b7183468-edaa-4067-bac5-c6e7ca4088e3	62d7dc96-16f0-4f35-b10d-6ebdf2b88cb9	allowed-protocol-mapper-types	oidc-usermodel-property-mapper
ab01cdf4-902f-407f-a575-1e4b2a5ca1ee	62d7dc96-16f0-4f35-b10d-6ebdf2b88cb9	allowed-protocol-mapper-types	saml-user-property-mapper
cdc7248e-b6f1-4480-ab44-8909ad2e9510	62d7dc96-16f0-4f35-b10d-6ebdf2b88cb9	allowed-protocol-mapper-types	oidc-address-mapper
3f6d0258-f2f4-4d24-bbbf-d8e5ec45bae9	62d7dc96-16f0-4f35-b10d-6ebdf2b88cb9	allowed-protocol-mapper-types	saml-user-attribute-mapper
2dd418a2-8143-418a-b166-d754bb4b8db4	0b857494-29fa-4f46-80a7-647df6601411	privateKey	MIIEpAIBAAKCAQEAsCr0nK2poLHlZMKNG6pBkfrHJ9WQ7iOFneu3p/m5cN1bnVi8pKibzQbrBJdlUtz6hWbTe2Wud31F1x+DZnQ08oqz3QGRszFCM3rlfIlyrz/5tGp0M/X0qnqxrgW3vL5T9aMk7zw57vbHgRq48AnbD+Nm2iK8ViKbBhqo9r75m5CwHQrIz+JpokGSfrslICD0Tt01dlIs5J1V554HFIOB65mLkTc+M1RQLlcET+wo1Ge9ATsEGoMoeze9T8ODGU1UmkRoQ4Y3L8CekaoEgRHgsS2wpgh/jI3oAMCTcnhbXhN97iFEpOqQ8s/SzZr8l+kjISXBH0tOj/CaAh9b50aclwIDAQABAoIBAELYyeD59LfJSSYmvKyWujLOWeu/mjMCv5zg6NuQYtF07WKTXWGNqTDvQxaG7Ce5OkaMcgsM1lr46htrFc02ozC1ePKPud2o/1nRdGsBLMdbG0Fec6GT3rchv3ItMT8paWp38Xfl/oWylplirnJHCxzISSrUq2pzzydNzndyl/xzFXXDtzxQcOtVVUQwd0Uubp+t9XdEDg/UJn2djrFBRfE6OD6Xxg6nBVn0j5jQ349tFP1UAIqQwK6OjuEM01h8+8W0Qrnb1b20bwBDHHMCJhNv2iuPFjNbdtDN01nxBlKa6T+/D0fJLuB5UAoPQYMcPtbW4/YybwN4jhDGbVzBM6ECgYEA1T+yFm6j19EN9+VFw95QmxzsDcS7Qy5aC90a7Kv/PjIj2FwHZxze8X/ncUqlFAsXZVznzSWoEMQjoQ4yvLM6p8+CCzemwtu43hrswiRuTl500jmlGIsjgOv4zOzezGIf+aZNoUjHpDDILzCfnsm6YMm8o67J2ZD5WLh6+em+/wUCgYEA03wyZDmNfndUSufNInHPKAHsU1REDODw6Rdb5iqWD7uZbUe3bkQngNk9nDBitRZEj7Niwq+qGWkYqpG9sgsmWudWBXCwo8o6bxcP+jJ82ogxFyF5P9ygh1IBLNmjmmTmV2k36keAc9gOzHe5PWpkRQxJAkrYSahfyeaQbk+R5+sCgYAnhlXIyJr/nlTbdJhYtHT2OwcZijQ3QHkaJ9IcuchmS77PFEee+f/sfQt1uSMdsuyUMgMYx/j9mo0MBeirhwDBJ7nvwFHdXgJG0HC/jycOyX0Xle2evfNHqvUDbofhE/LfP861rRqruQrxjC6ZrMQpulqHcBcjhzZgFllcxtFKzQKBgQCiJ5ZTtrVBBKoDDR0CjhTybhcQBYpv/YF6l8iFAJ4yzfrkCZsh1uwbJXbR7V+hzcMgE8Fj2WEpPqYFEt5KR7ZO+RXB8hfeXk7TovFDO7bzsH1DaQ0Y5EfJuhzgkLeayEa9OxX+cniRWlZufFXyO0NKlhLcyRpxz8IygrC3hBcxpQKBgQCU0xHow0JEZeXk2I6JNqvYoTuTyW9WJIJhyWLPN0CzphHTzifRD1aGPgByU1Mi3/Ca7j44nEhInMB7mq7zeYKJFVrLSzl+HOOCOaUUh735ilAGuPBbaLPovF5UcR2sbXhSjz/NRUPYFca1AcDws2vD6UvsoaZvZoUD+D9kTUL38g==
ad024da6-f871-4515-ae9f-ee0baa84dfe0	0b857494-29fa-4f46-80a7-647df6601411	certificate	MIICmzCCAYMCBgGhXXL16TANBgkqhkiG9w0BAQsFADARMQ8wDQYDVQQDDAZtYXN0ZXIwHhcNMjYxMDIxMDc1MTE3WhcNMzYxMDIxMDc1MjU3WjARMQ8wDQYDVQQDDAZtYXN0ZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCwKvScramgseVkwo0bqkGR+scn1ZDuI4Wd67en+blw3VudWLykqJvNBusEl2VS3PqFZtN7Za53fUXXH4NmdDTyirPdAZGzMUIzeuV8iXKvP/m0anQz9fSqerGuBbe8vlP1oyTvPDnu9seBGrjwCdsP42baIrxWIpsGGqj2vvmbkLAdCsjP4mmiQZJ+uyUgIPRO3TV2UizknVXnngcUg4HrmYuRNz4zVFAuVwRP7CjUZ70BOwQagyh7N71Pw4MZTVSaRGhDhjcvwJ6RqgSBEeCxLbCmCH+MjegAwJNyeFteE33uIUSk6pDyz9LNmvyX6SMhJcEfS06P8JoCH1vnRpyXAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAAC4PtF9vCin2zbOlLTWIZUytT/cIR/ybk5QVItkZOPd+2i/OblI9RwPSxqfNtQxcMwSkzRC5NWpDwtJwGHO++5193lRPCbkDmZylfyU3d/+d0wKqljfrwex+gZqY3YuuhRQBeB+ne4vpRI80Wqs/MlI9abslp3TgVsjXScsHRzvyVAZsYxuTnlHp7z+SQg6rjtmnK0njvdwfYujjmOz7ud8sMebryAkfVLi1QW8naS/HIHVTXtG4vuVWAx7CybI31fnea65jB8MexOtu7UUYNN4QNKSkFjk1sCcLH8Z0ajPSR79N7ljVEdnnM3ggYeLcouJWYDY/E5wg2jin13ScWQ=
d89d80db-3748-4c90-bfcb-1bdc1c078a5a	0b857494-29fa-4f46-80a7-647df6601411	priority	100
6afb9d90-d700-45ec-837a-800e45459d8d	0b857494-29fa-4f46-80a7-647df6601411	keyUse	SIG
36cf06ca-b5af-4e37-87b8-68ee4d85689d	f7e87d11-592b-4636-bf51-c9b2284b12e8	kc.user.profile.config	{"attributes":[{"name":"username","displayName":"${username}","validations":{"length":{"min":3,"max":255},"username-prohibited-characters":{},"up-username-not-idn-homograph":{}},"permissions":{"view":["admin","user"],"edit":["admin","user"]},"multivalued":false},{"name":"email","displayName":"${email}","validations":{"email":{},"length":{"max":255}},"permissions":{"view":["admin","user"],"edit":["admin","user"]},"multivalued":false},{"name":"firstName","displayName":"${firstName}","validations":{"length":{"max":255},"person-name-prohibited-characters":{}},"permissions":{"view":["admin","user"],"edit":["admin","user"]},"multivalued":false},{"name":"lastName","displayName":"${lastName}","validations":{"length":{"max":255},"person-name-prohibited-characters":{}},"permissions":{"view":["admin","user"],"edit":["admin","user"]},"multivalued":false}],"groups":[{"name":"user-metadata","displayHeader":"User metadata","displayDescription":"Attributes, which refer to user metadata"}]}
38d295ce-035f-4e1a-a239-345e06c4bda6	8b88473a-e89d-4e1b-917f-d6d70770b723	priority	100
f19d58af-a2cd-48eb-a80c-11068ec1729f	8b88473a-e89d-4e1b-917f-d6d70770b723	privateKey	MIIEogIBAAKCAQEA0DzBLVqcdMVEv5GKRcEwRMNSOloPL8/I4nRN+tOcDpVztpysEs6St8tZ5HO5RdzYLhrybCD6IQDne86lbeN9DN67WmYKAylH5Z280cvYCEt8OuSNAF2CI8/CbB67ys8DHkp36bhnMfhemmoFNi475DGMNTZ6DacuS2vrOvX7++AQDasIqzm5stcB28s7y4kpryNy9Dde7YwQGjpnubNL3Yw1cQ93QhW4GE0dRGDHV4IXTQ+7/QlklXoU/XJedT0crLoSLWl7Js9T8MAvyTWR6tQCcKNneHV2bFE328O6s9O9bM56Rkt92PO965z937/K7sTk3v2JBGUqmqOtUm+aoQIDAQABAoIBABldfS54Hhy/Nsua/9vVV3rYy/hdpgHt7otfHWyTQCwqmkjBNtinnwmSVKXWTtgquY6MK8FuFunUQV48YrxK/J2HuAyf51JRQfe/ShPIH82K3FwUIPTNbx/Lm+QtrjRbGQckjQzEMJXOqj9m8LGT2inGu0x0EVP+bE41nBa3hfU9MpS+i+93WR57a+qFswodYi6IKgsDH27DnL8tUevybp6VkJ1aH5Zh2gUHNCxbQOPOZieAfiJl6pNmdVzOJIV0jV3RkzDJ8l6AyiD2AGLeDQnydFLyxmwfuu9meOr7+FnKUm0dH0h05XnuZrhbRNruYCC4XdmDtQs8pFAAE+p/21ECgYEA65AoU16VUs/pr57rhATcCs8fYFZx2vULtrg26Fig4ntTkwF6/mf1+S7VjG8bKULqXb8X1At/ipMpVpz3fQJexwsOWPzFBIh3XUi6Nhp9epPqWWVtszBYCVJv2NaeVsJFmK+pv2RRpHb0QE4SSSYEHVb28yXSWqt1KfRItw+mRUUCgYEA4k2xYKvPtQq9A4tbYv5t32o38MdbzfzUQU5zMBDsGqfmPr0Y2fAsPUvghLGAlTpLqRMga3Vedtgc1TumSltDlFAXYDinsnmvQ8nJc5wbBj9LdaApw1MsbqLcxnURRd8P+wEUCra+C1GE11mOxZZCI0/kTzzjAoMVyxNPc8HQz60CgYAFzgygWVFWtBbvI/xryW7euVHtntO5cJZ0Tz/TI/P7AM0Db2LniApQtK3AgzBpKOP7oWzl5c6jzJKVNtMGept5TjVxTfFQ9kfyvYsRMD/tWF3LDCvS4ZsZx7VH46oNO0ZZx+Jn/AHjCqdkOkhLEyvAyVbWkRUI9PazLPjpwfH3/QKBgBFbykZTB3yolTUHZHwkbgMcH6xdbmJPiWx0+wrt0V5+EIAxew2EibAt+MvU3bsUnKcca3kyqItPKm8Ew02i0H0444Ii9mIPSW1WthgjGkORaVVdcraj052s6mhipG+Km6wyOfpUaCFwIFNwcC4hx3Lz9txJHFSd/3bzRT3o2P6FAoGAF9fc2h65pL7HHh01SffDOLSRj/e3lcWUbF0e93XLauaXg7ny/MsY/dp11g0AaFZUF3xBOj6fjuqitAtzELioHHeGylW7oTCNeBO3/kRZ+o2bEonLUz38Nh3sOW4GNaNNhNBsF0Ic1Wnujo/A2IarwiOnjenY3n30DVaaWNA1PNc=
b471186e-dd02-4f85-9b4c-ddf3666c3656	8b88473a-e89d-4e1b-917f-d6d70770b723	algorithm	RSA-OAEP
a8d27716-dfd2-4263-a55d-a0845bb6d8dc	8b88473a-e89d-4e1b-917f-d6d70770b723	certificate	MIICmzCCAYMCBgGhXXL4mjANBgkqhkiG9w0BAQsFADARMQ8wDQYDVQQDDAZtYXN0ZXIwHhcNMjYxMDIxMDc1MTE4WhcNMzYxMDIxMDc1MjU4WjARMQ8wDQYDVQQDDAZtYXN0ZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDQPMEtWpx0xUS/kYpFwTBEw1I6Wg8vz8jidE3605wOlXO2nKwSzpK3y1nkc7lF3NguGvJsIPohAOd7zqVt430M3rtaZgoDKUflnbzRy9gIS3w65I0AXYIjz8JsHrvKzwMeSnfpuGcx+F6aagU2LjvkMYw1NnoNpy5La+s69fv74BANqwirObmy1wHbyzvLiSmvI3L0N17tjBAaOme5s0vdjDVxD3dCFbgYTR1EYMdXghdND7v9CWSVehT9cl51PRysuhItaXsmz1PwwC/JNZHq1AJwo2d4dXZsUTfbw7qz071sznpGS33Y873rnP3fv8ruxOTe/YkEZSqao61Sb5qhAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAKdO3CeHTdADTLb2ex510IQBGMXzVWegOoHZzq+3OftsVmFTQM12CDoNa3Bi85PIn4L337zBVd94DQ4xdA5K16tssF5ss8rl7qGT33eDxaWpykGyb2GVOLagCAYWuHYNNihlDlUfxj0yqI78lrDPUgtXqRja6lWtl+kvI3slNVZ8B+i0eNIBWM9tBDg7t4OU+QtRPb2fIXsAnF6VuO410MCQaAY24hxGrtM7V3QC+1CUOlZc6dRnhTbUIGtv5cjw0k0An7rLAA6IoZ2+uE8iHm8GGIQ/hQMi/YcFR45ms3VF261Sn16xwlXm8glUVqaGGgz6TrSt3h3VyFvX/9afOBw=
a516eac8-3c1d-416c-8912-aaa5b20e4119	8b88473a-e89d-4e1b-917f-d6d70770b723	keyUse	ENC
916967a2-8510-4955-ad7b-64791cef8176	0d07fdf1-d314-42d5-907e-42cb2bb0a799	kid	fc841c6b-3b3d-4672-a8d1-1ee61088b384
ccc2c6b3-92b0-47e2-9557-c5f100f6e5fa	0d07fdf1-d314-42d5-907e-42cb2bb0a799	priority	100
c5dc84c0-949f-49f0-af0c-bdbed2fc406b	0d07fdf1-d314-42d5-907e-42cb2bb0a799	secret	8Du23zkOxw84tteEoB9pS7QMzj4jDGA1MMPJCZEFFT6puW1_yM9nu2_Yde_3oFGm8ZFPXwxAfUnh1YCNOUu7UhwxVfuumoOpPCT7Qy7_eADXcdiMELKN5c3uDW_g24NFBCACje5yOmE_bhHgTN3D_KDP3l-MWn4Zyb5unXuCfto
3bf435cd-0f6f-4821-8761-3db474a908fe	0d07fdf1-d314-42d5-907e-42cb2bb0a799	algorithm	HS512
6225f148-d0d9-4b1e-9eb7-a431aa3a2ec8	955c0a2f-8893-43d4-8296-ba1e7057fb89	priority	100
73dc88f0-7d36-4302-bfe5-2b762f0cb2af	955c0a2f-8893-43d4-8296-ba1e7057fb89	secret	rFDBp_oBLsSo7_rkNLnZJ7_h3ewXsa6N1jZOdfi-fCg
b80799bb-7c4c-4c15-a3d2-ea30b0d11c22	955c0a2f-8893-43d4-8296-ba1e7057fb89	kid	27d6f06e-430c-4680-a82f-ea0b85b26bd3
b7a217ca-2ade-4d7f-89f7-c498f931ed5f	16787f78-eba0-4920-8162-cf35b5aba8bb	keyUse	ENC
7624ad12-b74b-4821-ac8a-82ace6addb1b	16787f78-eba0-4920-8162-cf35b5aba8bb	certificate	MIICoTCCAYkCBgGhXXp9ODANBgkqhkiG9w0BAQsFADAUMRIwEAYDVQQDDAllcnAtcmVhbG0wHhcNMjYxMDIxMDc1OTMwWhcNMzYxMDIxMDgwMTEwWjAUMRIwEAYDVQQDDAllcnAtcmVhbG0wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDVOkgicE5Fgkh7L+4r/Cg9+0NyOsHlIKl8R0cl5sBG1kMe8XywK3a8WMSlGacTJWadKCmPnikUu7/32UkSEdgc9hzUp7cwHvy6YNNsNzjABj4NwRUJpjdi6g0d0FniMltJfFSF99YsuI2vnG4AMlspQ+2dEbEL94GKMlr0CmZprDnG0ij+TRl5p9foKZMgPw0JZ4cSYc0Nso7FagqsxI5/AR+oKx1ZejRF/lS0BFl8JuNaO+z7dXpoAFiKnHWGzC/YfGmBwIMTPXjJUR3mbTY84BCIaQaeMcvM8LITiXEK3Xrurmiii5aH3baCHtYNhN58JyBksLXUNPyWTSUwLJZ5AgMBAAEwDQYJKoZIhvcNAQELBQADggEBAM4W/yQi1jQYgofAO0g4CM1moVmvtVZGzeIbfDZQ3i4OqkUTM7iv68+kr5tm/aIPlo6kmZrd4SvBpK6N6FRQjTuTjO4z5KE92FyOO8nGngpdEscg5RLQN5XsJs5fZa2P70azCGjiIkYWVE8/2L4qVjjLt40bHqhPJBFhPUgOJC7qLSNNDGxFJB+jB41P6JQ/F1awIni0Cmp60A+WfB6aI7x+XQHBo5OxtNiW0QyyAP7U+Iycem9A8lhxa9YAFrXnBC/ZCIJG+IGI9LHZiJ6/lpFiBNF85vVcwYtlKR7lmQfQt2djBpO2elkW2GxXjOzZnqkWe6iZEfJpQvBU2SKdjl8=
60d4201c-bdfb-40b4-aa27-40041095d9aa	16787f78-eba0-4920-8162-cf35b5aba8bb	algorithm	RSA-OAEP
5c6e1b98-b98e-4f22-9d9b-3f49281aa682	16787f78-eba0-4920-8162-cf35b5aba8bb	priority	100
078aa458-4e79-4888-bef1-f4d7001d4eec	16787f78-eba0-4920-8162-cf35b5aba8bb	privateKey	MIIEpAIBAAKCAQEA1TpIInBORYJIey/uK/woPftDcjrB5SCpfEdHJebARtZDHvF8sCt2vFjEpRmnEyVmnSgpj54pFLu/99lJEhHYHPYc1Ke3MB78umDTbDc4wAY+DcEVCaY3YuoNHdBZ4jJbSXxUhffWLLiNr5xuADJbKUPtnRGxC/eBijJa9Apmaaw5xtIo/k0ZeafX6CmTID8NCWeHEmHNDbKOxWoKrMSOfwEfqCsdWXo0Rf5UtARZfCbjWjvs+3V6aABYipx1hswv2HxpgcCDEz14yVEd5m02POAQiGkGnjHLzPCyE4lxCt167q5ooouWh922gh7WDYTefCcgZLC11DT8lk0lMCyWeQIDAQABAoIBACAgjG7X8gsqEqaw9ZdeAmg4XBSxgrZ1weOuT6uHxY/Gx805QHrAyb6eN17S6ygI2hmyy/RONc1gbo+3Bvn4g1H1ySlHbeQLvzOL1D85YM0aA66J2ZQfHbhDIJ/N3UUmJjf/yjJ3QadyVTLRBIf2DmM8z2f7muv9KmD6rlaX3I9uM8wJeVMO9HQF5Q9BXQV4O7jMcWTnoOIHjd2sKffC7mPOiodUIXg4BAPVHMe0ASLZH7Ati8opYfAEQv2NBQVKFdRCWWCRbWe6E/8J6dxWisfEIZ5GbxOg0Sr1w2OyEuof9yFrBgCJ1+abpDcHdoeLDQhe7YEhZIHvwjKqfH+tdTsCgYEA62ifnGS+dvXXCcQ7f5BphI5ru3DxpDpRdOdZlRAZ8Tz6ojiKTm5x7EIHsAxW3ZQub24JUmFLWgaGDS89yarUDZ2uu6J6giVAsVROl9FugdleikU4DKDcl2c3bSmEP2MJTk1KzFcnAjZK+8rBVoBFnTEgP8/YzOHa7znl2ZbcD2sCgYEA5+D4jsoo9IsXdnGkrK5usfkegSanryQS2RmZ4tm12VjDgMv4XQt6c1c4Lfk0n8cXJcNICDWR1pzeGAeQ2RdL9dYoE9AWFM918tBwIDb4/3yKB+47iDBHZ5sRIlf/IzXCpGVKRULuqNBcLIzUfoBpdabAd5utainCpQNo7/LPXqsCgYEA4eEN5d608yiJIZHtFUXYOZz+umhxNIfQyT+DsYg1nEhKpYVjEEbhgTUKc14jq5EXzUvkHevFhahk0BnYS71io339v4Tz0BU2sfCXSQ1n36hXEo3Abj2b7JrZkCEaCEhbEYsQjmnBwFmgMWIniXyjT2Vn8FLbUBwXGxyO8+3RUekCgYEAttDCZyGwBI2dI/8ZTCQClkLI8B5f2k/gpFXw48+t9fxrtyIZYJJqKoG7g1OVT9uRvm4mXoKNxtzKpbthUidx9hKwal6G6kVewt/fZyawTg4MbZBAU3Fs+pxhd+hU+ZerLB3H3q+UpngQE/e8mTf47Y9Y83RD1w2xrpPvqi6PnB0CgYBhRcyAvhiFTHWwjLwgAOeHLOQZly0LynyCjV9lH4ZWzYF071uqJ4d+ybCVx9NF2T38HnImXB4VSzLGi7KknrVTQnT+v6Gynrwz8CMUJFdhYipH9REzeHf5b93BWyeurPMIcce9sS7x+k8aBKypk3k+w0YwvSaygDmd9JZgdfPAhw==
c4dd1eb2-84da-40a5-a41c-9f59a30c204e	9e333e7f-bd80-4991-929e-b23d0ed159dc	certificate	MIICoTCCAYkCBgGhXXp6rTANBgkqhkiG9w0BAQsFADAUMRIwEAYDVQQDDAllcnAtcmVhbG0wHhcNMjYxMDIxMDc1OTMwWhcNMzYxMDIxMDgwMTEwWjAUMRIwEAYDVQQDDAllcnAtcmVhbG0wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDhBUJVvcXucFn24VZDqMzyjUz4P9MzwjyvOAQ4z7473Qa8W9JfK9RuLSWc4DkjHcNS3KiJ5xNqLKQVn1qgwcNdPddcikHERtPlcgqb5dHI8GivhR02ZxBUG7rECGjv3Ogjm+S8eZiM+2Wis39QHzJTE4gF97g4MbccjPSLv3Y9Lk41NWTerLzs2friEaG1hltscqX282Bo10ppNqCUayvWC9hM+r4dm/ANG2DHHl/EjcfA/teYkSe3Pw4fB9W9kRYJbQgrS3ujQNYDfCS9FjtqHvhG5ba6ynQO2lrtyKDQkdmw7HB7yoQndWNA9c1HzkQ0DKhy8RG1UxmE2MzFMsslAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAE8zSG4bbmMYZ0MVzbG5aK4sWC42KXV4vKHP3jSOVRiU3sV1hyHA738h0lJT3mmiext4zK/sJZRU9ZqQsFkgtnGcMAl+eU9xWXySav8rYiBtelgb0sb17agwmLxNmvnFBQrcaELb8KVAhce7GxQMaSv0SwH9c1r+kGbszvPc29dZ5EdmwYgVEZNthScB+yCiOL+KN7ZLVJuASzhSw8nByjApzh6Mdk66QCMn5p9u/8KVtaysfJCs9CH9SuoEAowttxQVEPhUHWu7iRW5dhBKrnP8MDtZgAb1LVIJpsyYfkf65smJbYxpo4pF/vQzxu5SXqIbunLiBMKDqLKTeCrh/VE=
4c3c8254-d8c3-455d-8adb-28bbbbd30949	9e333e7f-bd80-4991-929e-b23d0ed159dc	keyUse	SIG
2a30772a-e318-48c6-9ffe-a60f4a897e36	9e333e7f-bd80-4991-929e-b23d0ed159dc	privateKey	MIIEowIBAAKCAQEA4QVCVb3F7nBZ9uFWQ6jM8o1M+D/TM8I8rzgEOM++O90GvFvSXyvUbi0lnOA5Ix3DUtyoiecTaiykFZ9aoMHDXT3XXIpBxEbT5XIKm+XRyPBor4UdNmcQVBu6xAho79zoI5vkvHmYjPtlorN/UB8yUxOIBfe4ODG3HIz0i792PS5ONTVk3qy87Nn64hGhtYZbbHKl9vNgaNdKaTaglGsr1gvYTPq+HZvwDRtgxx5fxI3HwP7XmJEntz8OHwfVvZEWCW0IK0t7o0DWA3wkvRY7ah74RuW2usp0Dtpa7cig0JHZsOxwe8qEJ3VjQPXNR85ENAyocvERtVMZhNjMxTLLJQIDAQABAoIBAEyCKELU6pae1sftaBJLM5wI1THXKa2AjneZGT5jzC+4gBDNO6MmWO05Jn/HcUXyWbYz1o5E5kIEeansa7kbCJ0MaMxLKf9dgbCS7O6C3qhurXl4Ti1wL4oZf5Alt+BOgROSbtxyj57n32/JjjEk2kyK6IX260kYBkWL254kdERqde+qR592Br+sEr++GIaD9RX1x2v2LXuANcCE1n2f/5z5vK0ZOtQNfW8PdmVsJJ66bfhCscz4+eJ3Jh+WBA3ADQkqhQTBVVAMKgHfYgj9VSvCB+zT0LYyVKJap+5QTGJbr3MW7Rj7YGVVpFGBYv8M5j2jcmDBNRsDw51eRJiWGWUCgYEA8XyURbc4ni5pXCyi7430FcxP6vFCUVlVhAl17D1DpRkrRDUQvVjuPmnppJqGAwm7TpLSWDN44UtGxorTzj/WBP8qyVbRtAtEscmxWkrdma5SUzfsJW/zh2Nw8QlJEbMG2NfJK4D1lrmQJik2frjxxYYwfjxUXebTQOPA7V1SegcCgYEA7otWw6l8QGiuApS/ymxEfMWLRbE+Yt+aZFtJ1P9Fy8XhWit935MUIchca97PsNPg0IgWWNHwr+SxAloO1VifFTU7LYZoIeaqK3xxxFGIMDbCY5wUoOHYThiqMchfIViSDEsclLkck89o+28QWl/xcliA41CjdZIJWITDhiEztnMCgYAuKoPqJBH146eO0JXBuGCufiXVI5RrGuoHWQurQzcYbAxieMaffE3nrrXVGxl9oTGm3tjJteVpJMv+DvJZHskaoXGbljZ29iSG3KlEOsXMqI/iivFhYtqqym8AFadbc99eOzqhT4Ej9IvDT+O0LEVEXtgMehoi7Yr7f88VUd7/pwKBgAMxMCcMJJKEFBgKv4pI6p200wlKtugB0AIZyqIkDF4OttZLELMmN7XABaSX5bWbED4aJBpqLMtdxxSd+ebW+cIB5VnVm50ghhRw5ODYqnbitLU6iHgirY9V+ykRYlyC3+l0M9y1oXFE7EW5FcHv2L5L+uWP1bAkFSXvGOK5nQSLAoGBAOg1wXXRhiWzpMLk/4k4VvLesN7AKlodC7RUaU2ycBIQKR5Z+ikYoAFa1ex2Qt894WQ0/6mHEuyKotAiP+akuYOVfNgGLE9yDTavTjus2Sd1nsTC13Tq3nT7pxabcgV1UAWC/80QUNV2BDPZMJrrnjomDTYqiK+O3/dNTHVjMBlS
2b6eb7d3-fbf6-401f-869b-20c3706e6c01	9e333e7f-bd80-4991-929e-b23d0ed159dc	priority	100
2b0a34f0-f31a-4228-ac5b-46ad519aa89f	0104cc11-8104-4b83-afa8-bbfa7d3defc4	algorithm	HS512
7453172e-6673-4557-a52e-1a0322fa7684	0104cc11-8104-4b83-afa8-bbfa7d3defc4	secret	vxH6JETNsBhlJIVpFpqFdW-r9GxRa9Z418s3xzp7jbiIrJZ0_wYuUhLKq548iF4EJF_6dN-Mkvbg_54r7n6EdY4rY42lpdqf_7D4fkU_RPZjLxrkJ81arRjkY_sBSEmF3T1vVrzhe9pLHq8iuf3krus9WJ3k82_A7uJ2bUwcn9c
bca149d3-8cdd-4241-b117-bad40d09b10a	0104cc11-8104-4b83-afa8-bbfa7d3defc4	priority	100
bbfdd5f1-94ec-494e-b7c0-57dbe0ef7a0a	0104cc11-8104-4b83-afa8-bbfa7d3defc4	kid	fc0475cc-7abc-4673-995b-1db36eb5046b
39801ef4-0187-4017-a80f-33b371f5481f	2900dcf3-420d-46c8-b634-651a8235eb92	kid	daafa45d-bea0-4fcb-b443-2ec2fc0b9500
8d1e07b5-d9a0-4d51-a070-2b0f34f9647e	2900dcf3-420d-46c8-b634-651a8235eb92	secret	TSOx-Ln_-xzo_GKox7sGfNE1fo7HBvj2uPwue-ViVMg
8c4afa11-bb13-41ae-b585-8fbcffdea23f	2900dcf3-420d-46c8-b634-651a8235eb92	priority	100
0efdcfdb-2b3e-46cc-9b1f-000338c7531d	982d05e0-abc1-43c2-a827-fe3d1f565665	allowed-protocol-mapper-types	oidc-usermodel-attribute-mapper
16c045e6-e387-4c53-b595-db55a6dd17fc	982d05e0-abc1-43c2-a827-fe3d1f565665	allowed-protocol-mapper-types	saml-role-list-mapper
47f49cc6-d54c-4d6f-81f7-8c8198d11f24	982d05e0-abc1-43c2-a827-fe3d1f565665	allowed-protocol-mapper-types	oidc-address-mapper
de6604dc-bbcd-48d7-8e40-38befd59b15f	982d05e0-abc1-43c2-a827-fe3d1f565665	allowed-protocol-mapper-types	oidc-full-name-mapper
ebccd847-3c01-4991-816b-a97391f9f256	982d05e0-abc1-43c2-a827-fe3d1f565665	allowed-protocol-mapper-types	saml-user-attribute-mapper
9637b2cb-c2d3-432e-9b7d-425659ed524d	982d05e0-abc1-43c2-a827-fe3d1f565665	allowed-protocol-mapper-types	saml-user-property-mapper
d74716ca-6414-43b9-ac35-eb1e849283ee	982d05e0-abc1-43c2-a827-fe3d1f565665	allowed-protocol-mapper-types	oidc-usermodel-property-mapper
c8f64d77-8268-46d5-9f51-7cd7bec9f00d	982d05e0-abc1-43c2-a827-fe3d1f565665	allowed-protocol-mapper-types	oidc-sha256-pairwise-sub-mapper
69bbb92b-2c44-4c61-97d8-ee182fc97406	d0f65beb-46ee-4054-af72-0e191cbe50bf	max-clients	200
d24e9a17-d642-4a7a-ac75-887cd6991cc7	b9295b49-8211-4e7b-9c8c-6f74d694868c	host-sending-registration-request-must-match	true
53ad98d3-54e1-4656-b8e4-2e9008ec6c12	b9295b49-8211-4e7b-9c8c-6f74d694868c	client-uris-must-match	true
d33c3090-1ae6-4c2b-9789-5d56bc6a0dce	b9e00810-3d40-437a-8312-408fa0a6c744	allowed-protocol-mapper-types	saml-user-property-mapper
a2130edc-abc9-412b-8f73-e0b6211d800f	b9e00810-3d40-437a-8312-408fa0a6c744	allowed-protocol-mapper-types	oidc-usermodel-property-mapper
8ea380f7-9430-46dc-bf9b-eeb2336f41e8	b9e00810-3d40-437a-8312-408fa0a6c744	allowed-protocol-mapper-types	saml-role-list-mapper
a942c99c-bf29-4096-bdc3-280407f1e6b1	b9e00810-3d40-437a-8312-408fa0a6c744	allowed-protocol-mapper-types	saml-user-attribute-mapper
062f57ba-c839-44cc-9018-ee89b4558012	b9e00810-3d40-437a-8312-408fa0a6c744	allowed-protocol-mapper-types	oidc-sha256-pairwise-sub-mapper
231a5131-4758-4ab5-9761-d1e8da71c006	b9e00810-3d40-437a-8312-408fa0a6c744	allowed-protocol-mapper-types	oidc-full-name-mapper
4789d9a9-6e13-404e-a3e5-5ba9d76d5310	b9e00810-3d40-437a-8312-408fa0a6c744	allowed-protocol-mapper-types	oidc-address-mapper
8b899943-ed5c-4f4a-82cf-eb04bc7991b2	b9e00810-3d40-437a-8312-408fa0a6c744	allowed-protocol-mapper-types	oidc-usermodel-attribute-mapper
75a87e75-c6d1-461d-9f73-5feef4872671	8c2f3f94-0d7a-4ca3-bae4-21e8e598abb8	allow-default-scopes	true
b2ed2d8d-a28c-4d5c-a3da-6530fa0778af	eefc06de-bb12-4e04-b5ca-e2801631d8a4	allow-default-scopes	true
\.


--
-- Data for Name: composite_role; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.composite_role (composite, child_role) FROM stdin;
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	a380ad84-fdfa-4ccb-bcb5-ab574d29c072
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	dbcedcf7-33b4-4a21-9ff7-b0e7ce50ebff
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	b48fd3c0-57eb-4369-aec5-a70d016e9986
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	f1ac4b3a-f1ec-4f75-b990-dab190c5e9b4
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	4354b90b-9164-4db2-8f4e-647c86099f18
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	75bb6ec6-77eb-46e9-8ef6-44e45051bf68
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	f25e0b6f-e43b-4339-adde-73c85ee643ba
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	07f98a6a-d429-4c57-86f4-69615777cca2
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	b9a246e6-2fc1-4f88-ad50-054a7daa49f5
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	3a19712f-6a6f-472a-9af3-075280f76d1e
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	af6f94a6-f00c-4f5e-9698-fd28abbf0203
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	bf782661-f931-431c-9155-ac6e3b2de258
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	773c4c39-a97c-4890-a07b-e90599e413d1
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	eb9e2689-d5d8-4964-99ef-7485be99e128
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	644e2703-adad-42f6-a9e2-ed6601dbcdc1
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	7f019472-88cd-4ad4-be44-4e9793dcd48e
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	ba8085d6-b032-4c48-8431-6ec73b37fc97
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	d3d07e72-5ad1-4caa-a3b0-0445cfbdefbc
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	4a6091d3-1240-4c0c-81f9-5a8c1278611f
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	b36d4994-157f-4df3-9854-5b4f9f3c0a3d
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	29ae07d6-982d-4365-9442-358587c50f3a
4354b90b-9164-4db2-8f4e-647c86099f18	d3d07e72-5ad1-4caa-a3b0-0445cfbdefbc
f1ac4b3a-f1ec-4f75-b990-dab190c5e9b4	ba8085d6-b032-4c48-8431-6ec73b37fc97
f1ac4b3a-f1ec-4f75-b990-dab190c5e9b4	b36d4994-157f-4df3-9854-5b4f9f3c0a3d
b9a246e6-2fc1-4f88-ad50-054a7daa49f5	29ae07d6-982d-4365-9442-358587c50f3a
6cf9ef6c-622a-4974-a502-6f878870e46a	1ee9d24a-9b6f-4b3d-9a62-d71b0f447176
6cf9ef6c-622a-4974-a502-6f878870e46a	0e3782ab-601b-42e1-ac5a-8666e6c7a872
0e3782ab-601b-42e1-ac5a-8666e6c7a872	b93f6df8-bb40-4f99-b183-35f633692751
d44b0920-a48e-4385-b3cd-ba65dd2c25fc	c8c3eeb9-f43c-4997-85be-b3b82fc5d9da
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	0664e646-4f22-46a0-aeed-56039423812b
6cf9ef6c-622a-4974-a502-6f878870e46a	6c27b134-5f46-42ed-b519-f9c86c2f64bd
6cf9ef6c-622a-4974-a502-6f878870e46a	29769b02-d59f-408f-be28-433f2ef47b9a
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	4757c5dd-6689-4f7f-9301-556b5e4b6c4c
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	57e02dd4-b3d4-45a5-b7ca-dc45b754e24e
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	b13ff089-8df2-4f94-ac69-641994228d6c
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	8dab97a1-8f55-46cc-aa38-d82433abd0fd
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	fa9ccdd7-62d1-4d3f-be18-0a5a022de995
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	5a5b207b-a126-49b9-af8a-e58c8b4deca1
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	c0e61e8c-6ae5-4b5f-9c5c-c6d44abd4824
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	250f7371-b0e8-4104-bc9e-0ff9e90cb22c
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	f928a9c5-db68-4eeb-9ecd-535ddfe1cbdf
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	09bc0318-fffe-40be-a0e5-d210d5965d0a
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	0e4f4637-5678-4f43-be31-0bab824d5d61
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	34c0f251-44ec-4152-b24f-af83c1288092
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	83541d45-c642-45de-bbbb-ca33a6a8b79a
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	1f725527-ac1d-467f-a764-d8e0d711d80d
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	bfc6f86e-6f00-424c-94cb-0f08e09b2b1f
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	a43ea015-bf0b-47ba-9376-66ebd05649e9
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	668bad6e-205e-4db2-84ad-d95bb7d59ca8
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	d2e7fa26-68a2-445f-ac32-8e4892c1eb06
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	c690a900-4115-4aaa-bdb0-5ff0e53e9814
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	277f80a5-3d1b-4a0f-b09d-32b9514fdf5c
8dab97a1-8f55-46cc-aa38-d82433abd0fd	668bad6e-205e-4db2-84ad-d95bb7d59ca8
b13ff089-8df2-4f94-ac69-641994228d6c	a43ea015-bf0b-47ba-9376-66ebd05649e9
b13ff089-8df2-4f94-ac69-641994228d6c	c690a900-4115-4aaa-bdb0-5ff0e53e9814
250f7371-b0e8-4104-bc9e-0ff9e90cb22c	277f80a5-3d1b-4a0f-b09d-32b9514fdf5c
97ef20f0-018b-4b7a-90e0-9906bb036a9e	a8106fab-5b5b-447d-926e-37f11f0feeb0
97ef20f0-018b-4b7a-90e0-9906bb036a9e	4cea49bc-9cb4-4650-83e9-9a8b097a4679
97ef20f0-018b-4b7a-90e0-9906bb036a9e	bb4d2ef9-1e42-4ca8-bf51-6b6e71ac9624
97ef20f0-018b-4b7a-90e0-9906bb036a9e	476d9f21-9bbb-48f7-9f75-aa4901ea80fe
97ef20f0-018b-4b7a-90e0-9906bb036a9e	7f818540-98d8-4017-aece-264f674d5aa2
97ef20f0-018b-4b7a-90e0-9906bb036a9e	64bc1cf1-48e3-4068-aa0b-5e5712a8dfab
97ef20f0-018b-4b7a-90e0-9906bb036a9e	66799bec-68ae-4665-b0db-e166d9b0cfb8
97ef20f0-018b-4b7a-90e0-9906bb036a9e	9eb6a249-3911-46d3-825e-737d53397d23
97ef20f0-018b-4b7a-90e0-9906bb036a9e	54823542-84d5-411c-a78f-d86ec7b31057
97ef20f0-018b-4b7a-90e0-9906bb036a9e	935f5ae3-f230-4e73-b37d-60452cc33867
97ef20f0-018b-4b7a-90e0-9906bb036a9e	2de2c0b9-a573-4b33-877d-1efe2d400a52
97ef20f0-018b-4b7a-90e0-9906bb036a9e	8bae4033-a12a-4388-80eb-b064a9cf38d0
97ef20f0-018b-4b7a-90e0-9906bb036a9e	a0c8b708-68ef-48ff-abdc-a76cf807d879
97ef20f0-018b-4b7a-90e0-9906bb036a9e	228d41b4-b59b-4049-9021-c112d753807a
97ef20f0-018b-4b7a-90e0-9906bb036a9e	d647696e-e53e-4039-84cc-5dcd11241f8e
97ef20f0-018b-4b7a-90e0-9906bb036a9e	9f49c0ba-388c-4367-9244-8453e205c995
97ef20f0-018b-4b7a-90e0-9906bb036a9e	4d092a0b-dc97-402f-a59a-32615baa88aa
97ef20f0-018b-4b7a-90e0-9906bb036a9e	c573e8b0-5ec2-4f86-bab2-22674c666d83
97ef20f0-018b-4b7a-90e0-9906bb036a9e	cd1e2b44-4726-4424-bcc4-0c43f7aca7aa
97ef20f0-018b-4b7a-90e0-9906bb036a9e	2c6b549a-14f0-4a95-a180-caae6fef4b51
476d9f21-9bbb-48f7-9f75-aa4901ea80fe	4d092a0b-dc97-402f-a59a-32615baa88aa
bb4d2ef9-1e42-4ca8-bf51-6b6e71ac9624	9f49c0ba-388c-4367-9244-8453e205c995
bb4d2ef9-1e42-4ca8-bf51-6b6e71ac9624	cd1e2b44-4726-4424-bcc4-0c43f7aca7aa
9eb6a249-3911-46d3-825e-737d53397d23	2c6b549a-14f0-4a95-a180-caae6fef4b51
28e26c46-098c-4b01-8576-0d5799ac35c4	5149e6e2-7f44-4c8f-bf73-dfe109e1169b
28e26c46-098c-4b01-8576-0d5799ac35c4	9ff03eea-be92-48e4-a780-af4078238a0a
9ff03eea-be92-48e4-a780-af4078238a0a	85d0a6a8-004c-42de-8dc0-885131ffdd8b
802fd728-3bed-4f31-9931-d95983d6d45b	5efe3d6e-8bf8-484e-8685-284026ebf2ab
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	1797b55b-bcfd-4c8e-baa2-2eba6861b47f
97ef20f0-018b-4b7a-90e0-9906bb036a9e	02b78066-9bae-42c8-b4c1-e786fe9ca4c2
28e26c46-098c-4b01-8576-0d5799ac35c4	c7fd25b0-998c-479f-9277-86d868a80406
28e26c46-098c-4b01-8576-0d5799ac35c4	e8bc09aa-0214-4146-a484-b2d1021a0cac
\.


--
-- Data for Name: credential; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.credential (id, salt, type, user_id, created_date, user_label, secret_data, credential_data, priority, version) FROM stdin;
bd23695a-2b66-4d28-82e5-4f0967a4eebb	\N	password	cbbffc68-782b-4fe9-8df5-9af0b51dac5a	1792569179315	\N	{"value":"pVaqaRk+T2/d1fIlZx2GMri7mSRQtYKNJ8Bnw570GSM=","salt":"0h7+iOwm+YxZXHvI5j3Vdw==","additionalParameters":{}}	{"hashIterations":5,"algorithm":"argon2","additionalParameters":{"hashLength":["32"],"memory":["7168"],"type":["id"],"version":["1.3"],"parallelism":["1"]}}	10	0
5e534742-b8ee-4d25-bf68-1406b731cb1e	\N	password	7660c2e6-a59f-4598-9c3d-05b7101f7c74	1792727183829	My password	{"value":"TpnbhcQq4PaUMKfPltcUrQTZiEdHKzPBVHWpqgZJqeQ=","salt":"p1nKnmXtLyqIlMFYEUxQzg==","additionalParameters":{}}	{"hashIterations":5,"algorithm":"argon2","additionalParameters":{"hashLength":["32"],"memory":["7168"],"type":["id"],"version":["1.3"],"parallelism":["1"]}}	10	1
1e6bc02b-6361-4acd-a98c-bdfde893508f	\N	password	b525b1f0-73bf-493b-9232-8fdf59a01651	1792742555753	My password	{"value":"jEQ32PeiFCS6ebbypmmBHFHHif9K7uyxZDjlwCMxo5s=","salt":"OYYFOuDIlCLMwUWN/G2k+g==","additionalParameters":{}}	{"hashIterations":5,"algorithm":"argon2","additionalParameters":{"hashLength":["32"],"memory":["7168"],"type":["id"],"version":["1.3"],"parallelism":["1"]}}	10	1
a3c826b6-ae04-4bb9-ba14-f436cf9bf4a5	\N	password	d0fd4cdb-45a8-4033-9baa-78433f03b8d9	1792573039331	My password	{"value":"/mFmi3ewzDaCMWYJM3zieic2HYL2pQLs0jWwGganEwM=","salt":"K1QQiv9XHNFA1o86uw6ebw==","additionalParameters":{}}	{"hashIterations":5,"algorithm":"argon2","additionalParameters":{"hashLength":["32"],"memory":["7168"],"type":["id"],"version":["1.3"],"parallelism":["1"]}}	10	1
013f6d6c-c5f0-45d3-902f-e87dec027133	\N	password	fa016850-0fe4-4927-8d04-1909b6ae1414	1793000025423	My password	{"value":"Fe8bgEU6WsLmWmFrKoPZ/Kl94B6IuOE4MHamKxJdFHs=","salt":"Sri7dZnMlHbUNeshNLHpGw==","additionalParameters":{}}	{"hashIterations":5,"algorithm":"argon2","additionalParameters":{"hashLength":["32"],"memory":["7168"],"type":["id"],"version":["1.3"],"parallelism":["1"]}}	10	6
\.


--
-- Data for Name: databasechangelog; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.databasechangelog (id, author, filename, dateexecuted, orderexecuted, exectype, md5sum, description, comments, tag, liquibase, contexts, labels, deployment_id) FROM stdin;
1.0.0.Final-KEYCLOAK-5461	sthorger@redhat.com	META-INF/jpa-changelog-1.0.0.Final.xml	2026-10-21 07:52:20.183062	1	EXECUTED	9:6f1016664e21e16d26517a4418f5e3df	createTable tableName=APPLICATION_DEFAULT_ROLES; createTable tableName=CLIENT; createTable tableName=CLIENT_SESSION; createTable tableName=CLIENT_SESSION_ROLE; createTable tableName=COMPOSITE_ROLE; createTable tableName=CREDENTIAL; createTable tab...		\N	4.33.0	\N	\N	2569129629
1.0.0.Final-KEYCLOAK-5461	sthorger@redhat.com	META-INF/db2-jpa-changelog-1.0.0.Final.xml	2026-10-21 07:52:20.238896	2	MARK_RAN	9:828775b1596a07d1200ba1d49e5e3941	createTable tableName=APPLICATION_DEFAULT_ROLES; createTable tableName=CLIENT; createTable tableName=CLIENT_SESSION; createTable tableName=CLIENT_SESSION_ROLE; createTable tableName=COMPOSITE_ROLE; createTable tableName=CREDENTIAL; createTable tab...		\N	4.33.0	\N	\N	2569129629
1.1.0.Beta1	sthorger@redhat.com	META-INF/jpa-changelog-1.1.0.Beta1.xml	2026-10-21 07:52:20.432423	3	EXECUTED	9:5f090e44a7d595883c1fb61f4b41fd38	delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION; createTable tableName=CLIENT_ATTRIBUTES; createTable tableName=CLIENT_SESSION_NOTE; createTable tableName=APP_NODE_REGISTRATIONS; addColumn table...		\N	4.33.0	\N	\N	2569129629
1.1.0.Final	sthorger@redhat.com	META-INF/jpa-changelog-1.1.0.Final.xml	2026-10-21 07:52:20.46655	4	EXECUTED	9:c07e577387a3d2c04d1adc9aaad8730e	renameColumn newColumnName=EVENT_TIME, oldColumnName=TIME, tableName=EVENT_ENTITY		\N	4.33.0	\N	\N	2569129629
1.2.0.Beta1	psilva@redhat.com	META-INF/jpa-changelog-1.2.0.Beta1.xml	2026-10-21 07:52:20.915839	5	EXECUTED	9:b68ce996c655922dbcd2fe6b6ae72686	delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION; createTable tableName=PROTOCOL_MAPPER; createTable tableName=PROTOCOL_MAPPER_CONFIG; createTable tableName=...		\N	4.33.0	\N	\N	2569129629
1.2.0.Beta1	psilva@redhat.com	META-INF/db2-jpa-changelog-1.2.0.Beta1.xml	2026-10-21 07:52:20.932754	6	MARK_RAN	9:543b5c9989f024fe35c6f6c5a97de88e	delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION; createTable tableName=PROTOCOL_MAPPER; createTable tableName=PROTOCOL_MAPPER_CONFIG; createTable tableName=...		\N	4.33.0	\N	\N	2569129629
1.2.0.RC1	bburke@redhat.com	META-INF/jpa-changelog-1.2.0.CR1.xml	2026-10-21 07:52:21.217205	7	EXECUTED	9:765afebbe21cf5bbca048e632df38336	delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION_NOTE; delete tableName=USER_SESSION; createTable tableName=MIGRATION_MODEL; createTable tableName=IDENTITY_P...		\N	4.33.0	\N	\N	2569129629
1.2.0.RC1	bburke@redhat.com	META-INF/db2-jpa-changelog-1.2.0.CR1.xml	2026-10-21 07:52:21.231878	8	MARK_RAN	9:db4a145ba11a6fdaefb397f6dbf829a1	delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION_NOTE; delete tableName=USER_SESSION; createTable tableName=MIGRATION_MODEL; createTable tableName=IDENTITY_P...		\N	4.33.0	\N	\N	2569129629
1.2.0.Final	keycloak	META-INF/jpa-changelog-1.2.0.Final.xml	2026-10-21 07:52:21.260726	9	EXECUTED	9:9d05c7be10cdb873f8bcb41bc3a8ab23	update tableName=CLIENT; update tableName=CLIENT; update tableName=CLIENT		\N	4.33.0	\N	\N	2569129629
1.3.0	bburke@redhat.com	META-INF/jpa-changelog-1.3.0.xml	2026-10-21 07:52:21.52527	10	EXECUTED	9:18593702353128d53111f9b1ff0b82b8	delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_PROT_MAPPER; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION_NOTE; delete tableName=USER_SESSION; createTable tableName=ADMI...		\N	4.33.0	\N	\N	2569129629
1.4.0	bburke@redhat.com	META-INF/jpa-changelog-1.4.0.xml	2026-10-21 07:52:21.684347	11	EXECUTED	9:6122efe5f090e41a85c0f1c9e52cbb62	delete tableName=CLIENT_SESSION_AUTH_STATUS; delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_PROT_MAPPER; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION_NOTE; delete table...		\N	4.33.0	\N	\N	2569129629
1.4.0	bburke@redhat.com	META-INF/db2-jpa-changelog-1.4.0.xml	2026-10-21 07:52:21.692927	12	MARK_RAN	9:e1ff28bf7568451453f844c5d54bb0b5	delete tableName=CLIENT_SESSION_AUTH_STATUS; delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_PROT_MAPPER; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION_NOTE; delete table...		\N	4.33.0	\N	\N	2569129629
1.5.0	bburke@redhat.com	META-INF/jpa-changelog-1.5.0.xml	2026-10-21 07:52:21.770659	13	EXECUTED	9:7af32cd8957fbc069f796b61217483fd	delete tableName=CLIENT_SESSION_AUTH_STATUS; delete tableName=CLIENT_SESSION_ROLE; delete tableName=CLIENT_SESSION_PROT_MAPPER; delete tableName=CLIENT_SESSION_NOTE; delete tableName=CLIENT_SESSION; delete tableName=USER_SESSION_NOTE; delete table...		\N	4.33.0	\N	\N	2569129629
1.6.1_from15	mposolda@redhat.com	META-INF/jpa-changelog-1.6.1.xml	2026-10-21 07:52:21.82173	14	EXECUTED	9:6005e15e84714cd83226bf7879f54190	addColumn tableName=REALM; addColumn tableName=KEYCLOAK_ROLE; addColumn tableName=CLIENT; createTable tableName=OFFLINE_USER_SESSION; createTable tableName=OFFLINE_CLIENT_SESSION; addPrimaryKey constraintName=CONSTRAINT_OFFL_US_SES_PK2, tableName=...		\N	4.33.0	\N	\N	2569129629
1.6.1_from16-pre	mposolda@redhat.com	META-INF/jpa-changelog-1.6.1.xml	2026-10-21 07:52:21.82794	15	MARK_RAN	9:bf656f5a2b055d07f314431cae76f06c	delete tableName=OFFLINE_CLIENT_SESSION; delete tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
1.6.1_from16	mposolda@redhat.com	META-INF/jpa-changelog-1.6.1.xml	2026-10-21 07:52:21.836484	16	MARK_RAN	9:f8dadc9284440469dcf71e25ca6ab99b	dropPrimaryKey constraintName=CONSTRAINT_OFFLINE_US_SES_PK, tableName=OFFLINE_USER_SESSION; dropPrimaryKey constraintName=CONSTRAINT_OFFLINE_CL_SES_PK, tableName=OFFLINE_CLIENT_SESSION; addColumn tableName=OFFLINE_USER_SESSION; update tableName=OF...		\N	4.33.0	\N	\N	2569129629
1.6.1	mposolda@redhat.com	META-INF/jpa-changelog-1.6.1.xml	2026-10-21 07:52:21.850387	17	EXECUTED	9:d41d8cd98f00b204e9800998ecf8427e	empty		\N	4.33.0	\N	\N	2569129629
1.7.0	bburke@redhat.com	META-INF/jpa-changelog-1.7.0.xml	2026-10-21 07:52:21.949932	18	EXECUTED	9:3368ff0be4c2855ee2dd9ca813b38d8e	createTable tableName=KEYCLOAK_GROUP; createTable tableName=GROUP_ROLE_MAPPING; createTable tableName=GROUP_ATTRIBUTE; createTable tableName=USER_GROUP_MEMBERSHIP; createTable tableName=REALM_DEFAULT_GROUPS; addColumn tableName=IDENTITY_PROVIDER; ...		\N	4.33.0	\N	\N	2569129629
1.8.0	mposolda@redhat.com	META-INF/jpa-changelog-1.8.0.xml	2026-10-21 07:52:22.066961	19	EXECUTED	9:8ac2fb5dd030b24c0570a763ed75ed20	addColumn tableName=IDENTITY_PROVIDER; createTable tableName=CLIENT_TEMPLATE; createTable tableName=CLIENT_TEMPLATE_ATTRIBUTES; createTable tableName=TEMPLATE_SCOPE_MAPPING; dropNotNullConstraint columnName=CLIENT_ID, tableName=PROTOCOL_MAPPER; ad...		\N	4.33.0	\N	\N	2569129629
1.8.0-2	keycloak	META-INF/jpa-changelog-1.8.0.xml	2026-10-21 07:52:22.108585	20	EXECUTED	9:f91ddca9b19743db60e3057679810e6c	dropDefaultValue columnName=ALGORITHM, tableName=CREDENTIAL; update tableName=CREDENTIAL		\N	4.33.0	\N	\N	2569129629
22.0.5-24031	keycloak	META-INF/jpa-changelog-22.0.0.xml	2026-10-21 07:52:33.550903	119	MARK_RAN	9:a60d2d7b315ec2d3eba9e2f145f9df28	customChange		\N	4.33.0	\N	\N	2569129629
1.8.0	mposolda@redhat.com	META-INF/db2-jpa-changelog-1.8.0.xml	2026-10-21 07:52:22.115276	21	MARK_RAN	9:831e82914316dc8a57dc09d755f23c51	addColumn tableName=IDENTITY_PROVIDER; createTable tableName=CLIENT_TEMPLATE; createTable tableName=CLIENT_TEMPLATE_ATTRIBUTES; createTable tableName=TEMPLATE_SCOPE_MAPPING; dropNotNullConstraint columnName=CLIENT_ID, tableName=PROTOCOL_MAPPER; ad...		\N	4.33.0	\N	\N	2569129629
1.8.0-2	keycloak	META-INF/db2-jpa-changelog-1.8.0.xml	2026-10-21 07:52:22.126964	22	MARK_RAN	9:f91ddca9b19743db60e3057679810e6c	dropDefaultValue columnName=ALGORITHM, tableName=CREDENTIAL; update tableName=CREDENTIAL		\N	4.33.0	\N	\N	2569129629
1.9.0	mposolda@redhat.com	META-INF/jpa-changelog-1.9.0.xml	2026-10-21 07:52:22.321041	23	EXECUTED	9:bc3d0f9e823a69dc21e23e94c7a94bb1	update tableName=REALM; update tableName=REALM; update tableName=REALM; update tableName=REALM; update tableName=CREDENTIAL; update tableName=CREDENTIAL; update tableName=CREDENTIAL; update tableName=REALM; update tableName=REALM; customChange; dr...		\N	4.33.0	\N	\N	2569129629
1.9.1	keycloak	META-INF/jpa-changelog-1.9.1.xml	2026-10-21 07:52:22.333139	24	EXECUTED	9:c9999da42f543575ab790e76439a2679	modifyDataType columnName=PRIVATE_KEY, tableName=REALM; modifyDataType columnName=PUBLIC_KEY, tableName=REALM; modifyDataType columnName=CERTIFICATE, tableName=REALM		\N	4.33.0	\N	\N	2569129629
1.9.1	keycloak	META-INF/db2-jpa-changelog-1.9.1.xml	2026-10-21 07:52:22.336402	25	MARK_RAN	9:0d6c65c6f58732d81569e77b10ba301d	modifyDataType columnName=PRIVATE_KEY, tableName=REALM; modifyDataType columnName=CERTIFICATE, tableName=REALM		\N	4.33.0	\N	\N	2569129629
1.9.2	keycloak	META-INF/jpa-changelog-1.9.2.xml	2026-10-21 07:52:23.272522	26	EXECUTED	9:fc576660fc016ae53d2d4778d84d86d0	createIndex indexName=IDX_USER_EMAIL, tableName=USER_ENTITY; createIndex indexName=IDX_USER_ROLE_MAPPING, tableName=USER_ROLE_MAPPING; createIndex indexName=IDX_USER_GROUP_MAPPING, tableName=USER_GROUP_MEMBERSHIP; createIndex indexName=IDX_USER_CO...		\N	4.33.0	\N	\N	2569129629
authz-2.0.0	psilva@redhat.com	META-INF/jpa-changelog-authz-2.0.0.xml	2026-10-21 07:52:23.465781	27	EXECUTED	9:43ed6b0da89ff77206289e87eaa9c024	createTable tableName=RESOURCE_SERVER; addPrimaryKey constraintName=CONSTRAINT_FARS, tableName=RESOURCE_SERVER; addUniqueConstraint constraintName=UK_AU8TT6T700S9V50BU18WS5HA6, tableName=RESOURCE_SERVER; createTable tableName=RESOURCE_SERVER_RESOU...		\N	4.33.0	\N	\N	2569129629
authz-2.5.1	psilva@redhat.com	META-INF/jpa-changelog-authz-2.5.1.xml	2026-10-21 07:52:23.481255	28	EXECUTED	9:44bae577f551b3738740281eceb4ea70	update tableName=RESOURCE_SERVER_POLICY		\N	4.33.0	\N	\N	2569129629
2.1.0-KEYCLOAK-5461	bburke@redhat.com	META-INF/jpa-changelog-2.1.0.xml	2026-10-21 07:52:23.641849	29	EXECUTED	9:bd88e1f833df0420b01e114533aee5e8	createTable tableName=BROKER_LINK; createTable tableName=FED_USER_ATTRIBUTE; createTable tableName=FED_USER_CONSENT; createTable tableName=FED_USER_CONSENT_ROLE; createTable tableName=FED_USER_CONSENT_PROT_MAPPER; createTable tableName=FED_USER_CR...		\N	4.33.0	\N	\N	2569129629
2.2.0	bburke@redhat.com	META-INF/jpa-changelog-2.2.0.xml	2026-10-21 07:52:23.680454	30	EXECUTED	9:a7022af5267f019d020edfe316ef4371	addColumn tableName=ADMIN_EVENT_ENTITY; createTable tableName=CREDENTIAL_ATTRIBUTE; createTable tableName=FED_CREDENTIAL_ATTRIBUTE; modifyDataType columnName=VALUE, tableName=CREDENTIAL; addForeignKeyConstraint baseTableName=FED_CREDENTIAL_ATTRIBU...		\N	4.33.0	\N	\N	2569129629
2.3.0	bburke@redhat.com	META-INF/jpa-changelog-2.3.0.xml	2026-10-21 07:52:23.737577	31	EXECUTED	9:fc155c394040654d6a79227e56f5e25a	createTable tableName=FEDERATED_USER; addPrimaryKey constraintName=CONSTR_FEDERATED_USER, tableName=FEDERATED_USER; dropDefaultValue columnName=TOTP, tableName=USER_ENTITY; dropColumn columnName=TOTP, tableName=USER_ENTITY; addColumn tableName=IDE...		\N	4.33.0	\N	\N	2569129629
2.4.0	bburke@redhat.com	META-INF/jpa-changelog-2.4.0.xml	2026-10-21 07:52:23.757107	32	EXECUTED	9:eac4ffb2a14795e5dc7b426063e54d88	customChange		\N	4.33.0	\N	\N	2569129629
2.5.0	bburke@redhat.com	META-INF/jpa-changelog-2.5.0.xml	2026-10-21 07:52:23.77792	33	EXECUTED	9:54937c05672568c4c64fc9524c1e9462	customChange; modifyDataType columnName=USER_ID, tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
2.5.0-unicode-oracle	hmlnarik@redhat.com	META-INF/jpa-changelog-2.5.0.xml	2026-10-21 07:52:23.783687	34	MARK_RAN	9:a9218de5ba87c6b32dc9a2a1706d95ba	modifyDataType columnName=DESCRIPTION, tableName=AUTHENTICATION_FLOW; modifyDataType columnName=DESCRIPTION, tableName=CLIENT_TEMPLATE; modifyDataType columnName=DESCRIPTION, tableName=RESOURCE_SERVER_POLICY; modifyDataType columnName=DESCRIPTION,...		\N	4.33.0	\N	\N	2569129629
2.5.0-unicode-other-dbs	hmlnarik@redhat.com	META-INF/jpa-changelog-2.5.0.xml	2026-10-21 07:52:23.884208	35	EXECUTED	9:33d72168746f81f98ae3a1e8e0ca3554	modifyDataType columnName=DESCRIPTION, tableName=AUTHENTICATION_FLOW; modifyDataType columnName=DESCRIPTION, tableName=CLIENT_TEMPLATE; modifyDataType columnName=DESCRIPTION, tableName=RESOURCE_SERVER_POLICY; modifyDataType columnName=DESCRIPTION,...		\N	4.33.0	\N	\N	2569129629
2.5.0-duplicate-email-support	slawomir@dabek.name	META-INF/jpa-changelog-2.5.0.xml	2026-10-21 07:52:23.900647	36	EXECUTED	9:61b6d3d7a4c0e0024b0c839da283da0c	addColumn tableName=REALM		\N	4.33.0	\N	\N	2569129629
2.5.0-unique-group-names	hmlnarik@redhat.com	META-INF/jpa-changelog-2.5.0.xml	2026-10-21 07:52:23.914114	37	EXECUTED	9:8dcac7bdf7378e7d823cdfddebf72fda	addUniqueConstraint constraintName=SIBLING_NAMES, tableName=KEYCLOAK_GROUP		\N	4.33.0	\N	\N	2569129629
2.5.1	bburke@redhat.com	META-INF/jpa-changelog-2.5.1.xml	2026-10-21 07:52:23.925747	38	EXECUTED	9:a2b870802540cb3faa72098db5388af3	addColumn tableName=FED_USER_CONSENT		\N	4.33.0	\N	\N	2569129629
3.0.0	bburke@redhat.com	META-INF/jpa-changelog-3.0.0.xml	2026-10-21 07:52:23.935236	39	EXECUTED	9:132a67499ba24bcc54fb5cbdcfe7e4c0	addColumn tableName=IDENTITY_PROVIDER		\N	4.33.0	\N	\N	2569129629
3.2.0-fix	keycloak	META-INF/jpa-changelog-3.2.0.xml	2026-10-21 07:52:23.939573	40	MARK_RAN	9:938f894c032f5430f2b0fafb1a243462	addNotNullConstraint columnName=REALM_ID, tableName=CLIENT_INITIAL_ACCESS		\N	4.33.0	\N	\N	2569129629
3.2.0-fix-with-keycloak-5416	keycloak	META-INF/jpa-changelog-3.2.0.xml	2026-10-21 07:52:23.946945	41	MARK_RAN	9:845c332ff1874dc5d35974b0babf3006	dropIndex indexName=IDX_CLIENT_INIT_ACC_REALM, tableName=CLIENT_INITIAL_ACCESS; addNotNullConstraint columnName=REALM_ID, tableName=CLIENT_INITIAL_ACCESS; createIndex indexName=IDX_CLIENT_INIT_ACC_REALM, tableName=CLIENT_INITIAL_ACCESS		\N	4.33.0	\N	\N	2569129629
3.2.0-fix-offline-sessions	hmlnarik	META-INF/jpa-changelog-3.2.0.xml	2026-10-21 07:52:23.963803	42	EXECUTED	9:fc86359c079781adc577c5a217e4d04c	customChange		\N	4.33.0	\N	\N	2569129629
3.2.0-fixed	keycloak	META-INF/jpa-changelog-3.2.0.xml	2026-10-21 07:52:27.714986	43	EXECUTED	9:59a64800e3c0d09b825f8a3b444fa8f4	addColumn tableName=REALM; dropPrimaryKey constraintName=CONSTRAINT_OFFL_CL_SES_PK2, tableName=OFFLINE_CLIENT_SESSION; dropColumn columnName=CLIENT_SESSION_ID, tableName=OFFLINE_CLIENT_SESSION; addPrimaryKey constraintName=CONSTRAINT_OFFL_CL_SES_P...		\N	4.33.0	\N	\N	2569129629
3.3.0	keycloak	META-INF/jpa-changelog-3.3.0.xml	2026-10-21 07:52:27.72488	44	EXECUTED	9:d48d6da5c6ccf667807f633fe489ce88	addColumn tableName=USER_ENTITY		\N	4.33.0	\N	\N	2569129629
authz-3.4.0.CR1-resource-server-pk-change-part1	glavoie@gmail.com	META-INF/jpa-changelog-authz-3.4.0.CR1.xml	2026-10-21 07:52:27.736511	45	EXECUTED	9:dde36f7973e80d71fceee683bc5d2951	addColumn tableName=RESOURCE_SERVER_POLICY; addColumn tableName=RESOURCE_SERVER_RESOURCE; addColumn tableName=RESOURCE_SERVER_SCOPE		\N	4.33.0	\N	\N	2569129629
authz-3.4.0.CR1-resource-server-pk-change-part2-KEYCLOAK-6095	hmlnarik@redhat.com	META-INF/jpa-changelog-authz-3.4.0.CR1.xml	2026-10-21 07:52:27.748962	46	EXECUTED	9:b855e9b0a406b34fa323235a0cf4f640	customChange		\N	4.33.0	\N	\N	2569129629
authz-3.4.0.CR1-resource-server-pk-change-part3-fixed	glavoie@gmail.com	META-INF/jpa-changelog-authz-3.4.0.CR1.xml	2026-10-21 07:52:27.752745	47	MARK_RAN	9:51abbacd7b416c50c4421a8cabf7927e	dropIndex indexName=IDX_RES_SERV_POL_RES_SERV, tableName=RESOURCE_SERVER_POLICY; dropIndex indexName=IDX_RES_SRV_RES_RES_SRV, tableName=RESOURCE_SERVER_RESOURCE; dropIndex indexName=IDX_RES_SRV_SCOPE_RES_SRV, tableName=RESOURCE_SERVER_SCOPE		\N	4.33.0	\N	\N	2569129629
authz-3.4.0.CR1-resource-server-pk-change-part3-fixed-nodropindex	glavoie@gmail.com	META-INF/jpa-changelog-authz-3.4.0.CR1.xml	2026-10-21 07:52:28.115814	48	EXECUTED	9:bdc99e567b3398bac83263d375aad143	addNotNullConstraint columnName=RESOURCE_SERVER_CLIENT_ID, tableName=RESOURCE_SERVER_POLICY; addNotNullConstraint columnName=RESOURCE_SERVER_CLIENT_ID, tableName=RESOURCE_SERVER_RESOURCE; addNotNullConstraint columnName=RESOURCE_SERVER_CLIENT_ID, ...		\N	4.33.0	\N	\N	2569129629
authn-3.4.0.CR1-refresh-token-max-reuse	glavoie@gmail.com	META-INF/jpa-changelog-authz-3.4.0.CR1.xml	2026-10-21 07:52:28.128314	49	EXECUTED	9:d198654156881c46bfba39abd7769e69	addColumn tableName=REALM		\N	4.33.0	\N	\N	2569129629
3.4.0	keycloak	META-INF/jpa-changelog-3.4.0.xml	2026-10-21 07:52:28.211962	50	EXECUTED	9:cfdd8736332ccdd72c5256ccb42335db	addPrimaryKey constraintName=CONSTRAINT_REALM_DEFAULT_ROLES, tableName=REALM_DEFAULT_ROLES; addPrimaryKey constraintName=CONSTRAINT_COMPOSITE_ROLE, tableName=COMPOSITE_ROLE; addPrimaryKey constraintName=CONSTR_REALM_DEFAULT_GROUPS, tableName=REALM...		\N	4.33.0	\N	\N	2569129629
3.4.0-KEYCLOAK-5230	hmlnarik@redhat.com	META-INF/jpa-changelog-3.4.0.xml	2026-10-21 07:52:29.134316	51	EXECUTED	9:7c84de3d9bd84d7f077607c1a4dcb714	createIndex indexName=IDX_FU_ATTRIBUTE, tableName=FED_USER_ATTRIBUTE; createIndex indexName=IDX_FU_CONSENT, tableName=FED_USER_CONSENT; createIndex indexName=IDX_FU_CONSENT_RU, tableName=FED_USER_CONSENT; createIndex indexName=IDX_FU_CREDENTIAL, t...		\N	4.33.0	\N	\N	2569129629
3.4.1	psilva@redhat.com	META-INF/jpa-changelog-3.4.1.xml	2026-10-21 07:52:29.142621	52	EXECUTED	9:5a6bb36cbefb6a9d6928452c0852af2d	modifyDataType columnName=VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.33.0	\N	\N	2569129629
3.4.2	keycloak	META-INF/jpa-changelog-3.4.2.xml	2026-10-21 07:52:29.15028	53	EXECUTED	9:8f23e334dbc59f82e0a328373ca6ced0	update tableName=REALM		\N	4.33.0	\N	\N	2569129629
3.4.2-KEYCLOAK-5172	mkanis@redhat.com	META-INF/jpa-changelog-3.4.2.xml	2026-10-21 07:52:29.157535	54	EXECUTED	9:9156214268f09d970cdf0e1564d866af	update tableName=CLIENT		\N	4.33.0	\N	\N	2569129629
4.0.0-KEYCLOAK-6335	bburke@redhat.com	META-INF/jpa-changelog-4.0.0.xml	2026-10-21 07:52:29.171058	55	EXECUTED	9:db806613b1ed154826c02610b7dbdf74	createTable tableName=CLIENT_AUTH_FLOW_BINDINGS; addPrimaryKey constraintName=C_CLI_FLOW_BIND, tableName=CLIENT_AUTH_FLOW_BINDINGS		\N	4.33.0	\N	\N	2569129629
4.0.0-CLEANUP-UNUSED-TABLE	bburke@redhat.com	META-INF/jpa-changelog-4.0.0.xml	2026-10-21 07:52:29.181416	56	EXECUTED	9:229a041fb72d5beac76bb94a5fa709de	dropTable tableName=CLIENT_IDENTITY_PROV_MAPPING		\N	4.33.0	\N	\N	2569129629
4.0.0-KEYCLOAK-6228	bburke@redhat.com	META-INF/jpa-changelog-4.0.0.xml	2026-10-21 07:52:29.297983	57	EXECUTED	9:079899dade9c1e683f26b2aa9ca6ff04	dropUniqueConstraint constraintName=UK_JKUWUVD56ONTGSUHOGM8UEWRT, tableName=USER_CONSENT; dropNotNullConstraint columnName=CLIENT_ID, tableName=USER_CONSENT; addColumn tableName=USER_CONSENT; addUniqueConstraint constraintName=UK_JKUWUVD56ONTGSUHO...		\N	4.33.0	\N	\N	2569129629
4.0.0-KEYCLOAK-5579-fixed	mposolda@redhat.com	META-INF/jpa-changelog-4.0.0.xml	2026-10-21 07:52:30.647074	58	EXECUTED	9:139b79bcbbfe903bb1c2d2a4dbf001d9	dropForeignKeyConstraint baseTableName=CLIENT_TEMPLATE_ATTRIBUTES, constraintName=FK_CL_TEMPL_ATTR_TEMPL; renameTable newTableName=CLIENT_SCOPE_ATTRIBUTES, oldTableName=CLIENT_TEMPLATE_ATTRIBUTES; renameColumn newColumnName=SCOPE_ID, oldColumnName...		\N	4.33.0	\N	\N	2569129629
authz-4.0.0.CR1	psilva@redhat.com	META-INF/jpa-changelog-authz-4.0.0.CR1.xml	2026-10-21 07:52:30.721788	59	EXECUTED	9:b55738ad889860c625ba2bf483495a04	createTable tableName=RESOURCE_SERVER_PERM_TICKET; addPrimaryKey constraintName=CONSTRAINT_FAPMT, tableName=RESOURCE_SERVER_PERM_TICKET; addForeignKeyConstraint baseTableName=RESOURCE_SERVER_PERM_TICKET, constraintName=FK_FRSRHO213XCX4WNKOG82SSPMT...		\N	4.33.0	\N	\N	2569129629
authz-4.0.0.Beta3	psilva@redhat.com	META-INF/jpa-changelog-authz-4.0.0.Beta3.xml	2026-10-21 07:52:30.736417	60	EXECUTED	9:e0057eac39aa8fc8e09ac6cfa4ae15fe	addColumn tableName=RESOURCE_SERVER_POLICY; addColumn tableName=RESOURCE_SERVER_PERM_TICKET; addForeignKeyConstraint baseTableName=RESOURCE_SERVER_PERM_TICKET, constraintName=FK_FRSRPO2128CX4WNKOG82SSRFY, referencedTableName=RESOURCE_SERVER_POLICY		\N	4.33.0	\N	\N	2569129629
authz-4.2.0.Final	mhajas@redhat.com	META-INF/jpa-changelog-authz-4.2.0.Final.xml	2026-10-21 07:52:30.757051	61	EXECUTED	9:42a33806f3a0443fe0e7feeec821326c	createTable tableName=RESOURCE_URIS; addForeignKeyConstraint baseTableName=RESOURCE_URIS, constraintName=FK_RESOURCE_SERVER_URIS, referencedTableName=RESOURCE_SERVER_RESOURCE; customChange; dropColumn columnName=URI, tableName=RESOURCE_SERVER_RESO...		\N	4.33.0	\N	\N	2569129629
authz-4.2.0.Final-KEYCLOAK-9944	hmlnarik@redhat.com	META-INF/jpa-changelog-authz-4.2.0.Final.xml	2026-10-21 07:52:30.768384	62	EXECUTED	9:9968206fca46eecc1f51db9c024bfe56	addPrimaryKey constraintName=CONSTRAINT_RESOUR_URIS_PK, tableName=RESOURCE_URIS		\N	4.33.0	\N	\N	2569129629
4.2.0-KEYCLOAK-6313	wadahiro@gmail.com	META-INF/jpa-changelog-4.2.0.xml	2026-10-21 07:52:30.776609	63	EXECUTED	9:92143a6daea0a3f3b8f598c97ce55c3d	addColumn tableName=REQUIRED_ACTION_PROVIDER		\N	4.33.0	\N	\N	2569129629
4.3.0-KEYCLOAK-7984	wadahiro@gmail.com	META-INF/jpa-changelog-4.3.0.xml	2026-10-21 07:52:30.784783	64	EXECUTED	9:82bab26a27195d889fb0429003b18f40	update tableName=REQUIRED_ACTION_PROVIDER		\N	4.33.0	\N	\N	2569129629
4.6.0-KEYCLOAK-7950	psilva@redhat.com	META-INF/jpa-changelog-4.6.0.xml	2026-10-21 07:52:30.792354	65	EXECUTED	9:e590c88ddc0b38b0ae4249bbfcb5abc3	update tableName=RESOURCE_SERVER_RESOURCE		\N	4.33.0	\N	\N	2569129629
4.6.0-KEYCLOAK-8377	keycloak	META-INF/jpa-changelog-4.6.0.xml	2026-10-21 07:52:30.915374	66	EXECUTED	9:5c1f475536118dbdc38d5d7977950cc0	createTable tableName=ROLE_ATTRIBUTE; addPrimaryKey constraintName=CONSTRAINT_ROLE_ATTRIBUTE_PK, tableName=ROLE_ATTRIBUTE; addForeignKeyConstraint baseTableName=ROLE_ATTRIBUTE, constraintName=FK_ROLE_ATTRIBUTE_ID, referencedTableName=KEYCLOAK_ROLE...		\N	4.33.0	\N	\N	2569129629
4.6.0-KEYCLOAK-8555	gideonray@gmail.com	META-INF/jpa-changelog-4.6.0.xml	2026-10-21 07:52:31.015261	67	EXECUTED	9:e7c9f5f9c4d67ccbbcc215440c718a17	createIndex indexName=IDX_COMPONENT_PROVIDER_TYPE, tableName=COMPONENT		\N	4.33.0	\N	\N	2569129629
4.7.0-KEYCLOAK-1267	sguilhen@redhat.com	META-INF/jpa-changelog-4.7.0.xml	2026-10-21 07:52:31.025062	68	EXECUTED	9:88e0bfdda924690d6f4e430c53447dd5	addColumn tableName=REALM		\N	4.33.0	\N	\N	2569129629
4.7.0-KEYCLOAK-7275	keycloak	META-INF/jpa-changelog-4.7.0.xml	2026-10-21 07:52:31.124268	69	EXECUTED	9:f53177f137e1c46b6a88c59ec1cb5218	renameColumn newColumnName=CREATED_ON, oldColumnName=LAST_SESSION_REFRESH, tableName=OFFLINE_USER_SESSION; addNotNullConstraint columnName=CREATED_ON, tableName=OFFLINE_USER_SESSION; addColumn tableName=OFFLINE_USER_SESSION; customChange; createIn...		\N	4.33.0	\N	\N	2569129629
4.8.0-KEYCLOAK-8835	sguilhen@redhat.com	META-INF/jpa-changelog-4.8.0.xml	2026-10-21 07:52:31.140286	70	EXECUTED	9:a74d33da4dc42a37ec27121580d1459f	addNotNullConstraint columnName=SSO_MAX_LIFESPAN_REMEMBER_ME, tableName=REALM; addNotNullConstraint columnName=SSO_IDLE_TIMEOUT_REMEMBER_ME, tableName=REALM		\N	4.33.0	\N	\N	2569129629
authz-7.0.0-KEYCLOAK-10443	psilva@redhat.com	META-INF/jpa-changelog-authz-7.0.0.xml	2026-10-21 07:52:31.151938	71	EXECUTED	9:fd4ade7b90c3b67fae0bfcfcb42dfb5f	addColumn tableName=RESOURCE_SERVER		\N	4.33.0	\N	\N	2569129629
8.0.0-adding-credential-columns	keycloak	META-INF/jpa-changelog-8.0.0.xml	2026-10-21 07:52:31.182366	72	EXECUTED	9:aa072ad090bbba210d8f18781b8cebf4	addColumn tableName=CREDENTIAL; addColumn tableName=FED_USER_CREDENTIAL		\N	4.33.0	\N	\N	2569129629
8.0.0-updating-credential-data-not-oracle-fixed	keycloak	META-INF/jpa-changelog-8.0.0.xml	2026-10-21 07:52:31.21612	73	EXECUTED	9:1ae6be29bab7c2aa376f6983b932be37	update tableName=CREDENTIAL; update tableName=CREDENTIAL; update tableName=CREDENTIAL; update tableName=FED_USER_CREDENTIAL; update tableName=FED_USER_CREDENTIAL; update tableName=FED_USER_CREDENTIAL		\N	4.33.0	\N	\N	2569129629
8.0.0-updating-credential-data-oracle-fixed	keycloak	META-INF/jpa-changelog-8.0.0.xml	2026-10-21 07:52:31.223892	74	MARK_RAN	9:14706f286953fc9a25286dbd8fb30d97	update tableName=CREDENTIAL; update tableName=CREDENTIAL; update tableName=CREDENTIAL; update tableName=FED_USER_CREDENTIAL; update tableName=FED_USER_CREDENTIAL; update tableName=FED_USER_CREDENTIAL		\N	4.33.0	\N	\N	2569129629
8.0.0-credential-cleanup-fixed	keycloak	META-INF/jpa-changelog-8.0.0.xml	2026-10-21 07:52:31.306726	75	EXECUTED	9:2b9cc12779be32c5b40e2e67711a218b	dropDefaultValue columnName=COUNTER, tableName=CREDENTIAL; dropDefaultValue columnName=DIGITS, tableName=CREDENTIAL; dropDefaultValue columnName=PERIOD, tableName=CREDENTIAL; dropDefaultValue columnName=ALGORITHM, tableName=CREDENTIAL; dropColumn ...		\N	4.33.0	\N	\N	2569129629
8.0.0-resource-tag-support	keycloak	META-INF/jpa-changelog-8.0.0.xml	2026-10-21 07:52:31.408586	76	EXECUTED	9:91fa186ce7a5af127a2d7a91ee083cc5	addColumn tableName=MIGRATION_MODEL; createIndex indexName=IDX_UPDATE_TIME, tableName=MIGRATION_MODEL		\N	4.33.0	\N	\N	2569129629
9.0.0-always-display-client	keycloak	META-INF/jpa-changelog-9.0.0.xml	2026-10-21 07:52:31.418663	77	EXECUTED	9:6335e5c94e83a2639ccd68dd24e2e5ad	addColumn tableName=CLIENT		\N	4.33.0	\N	\N	2569129629
9.0.0-drop-constraints-for-column-increase	keycloak	META-INF/jpa-changelog-9.0.0.xml	2026-10-21 07:52:31.422623	78	MARK_RAN	9:6bdb5658951e028bfe16fa0a8228b530	dropUniqueConstraint constraintName=UK_FRSR6T700S9V50BU18WS5PMT, tableName=RESOURCE_SERVER_PERM_TICKET; dropUniqueConstraint constraintName=UK_FRSR6T700S9V50BU18WS5HA6, tableName=RESOURCE_SERVER_RESOURCE; dropPrimaryKey constraintName=CONSTRAINT_O...		\N	4.33.0	\N	\N	2569129629
9.0.0-increase-column-size-federated-fk	keycloak	META-INF/jpa-changelog-9.0.0.xml	2026-10-21 07:52:31.460949	79	EXECUTED	9:d5bc15a64117ccad481ce8792d4c608f	modifyDataType columnName=CLIENT_ID, tableName=FED_USER_CONSENT; modifyDataType columnName=CLIENT_REALM_CONSTRAINT, tableName=KEYCLOAK_ROLE; modifyDataType columnName=OWNER, tableName=RESOURCE_SERVER_POLICY; modifyDataType columnName=CLIENT_ID, ta...		\N	4.33.0	\N	\N	2569129629
9.0.0-recreate-constraints-after-column-increase	keycloak	META-INF/jpa-changelog-9.0.0.xml	2026-10-21 07:52:31.46507	80	MARK_RAN	9:077cba51999515f4d3e7ad5619ab592c	addNotNullConstraint columnName=CLIENT_ID, tableName=OFFLINE_CLIENT_SESSION; addNotNullConstraint columnName=OWNER, tableName=RESOURCE_SERVER_PERM_TICKET; addNotNullConstraint columnName=REQUESTER, tableName=RESOURCE_SERVER_PERM_TICKET; addNotNull...		\N	4.33.0	\N	\N	2569129629
9.0.1-add-index-to-client.client_id	keycloak	META-INF/jpa-changelog-9.0.1.xml	2026-10-21 07:52:31.576382	81	EXECUTED	9:be969f08a163bf47c6b9e9ead8ac2afb	createIndex indexName=IDX_CLIENT_ID, tableName=CLIENT		\N	4.33.0	\N	\N	2569129629
9.0.1-KEYCLOAK-12579-drop-constraints	keycloak	META-INF/jpa-changelog-9.0.1.xml	2026-10-21 07:52:31.581045	82	MARK_RAN	9:6d3bb4408ba5a72f39bd8a0b301ec6e3	dropUniqueConstraint constraintName=SIBLING_NAMES, tableName=KEYCLOAK_GROUP		\N	4.33.0	\N	\N	2569129629
9.0.1-KEYCLOAK-12579-add-not-null-constraint	keycloak	META-INF/jpa-changelog-9.0.1.xml	2026-10-21 07:52:31.597324	83	EXECUTED	9:966bda61e46bebf3cc39518fbed52fa7	addNotNullConstraint columnName=PARENT_GROUP, tableName=KEYCLOAK_GROUP		\N	4.33.0	\N	\N	2569129629
9.0.1-KEYCLOAK-12579-recreate-constraints	keycloak	META-INF/jpa-changelog-9.0.1.xml	2026-10-21 07:52:31.601978	84	MARK_RAN	9:8dcac7bdf7378e7d823cdfddebf72fda	addUniqueConstraint constraintName=SIBLING_NAMES, tableName=KEYCLOAK_GROUP		\N	4.33.0	\N	\N	2569129629
9.0.1-add-index-to-events	keycloak	META-INF/jpa-changelog-9.0.1.xml	2026-10-21 07:52:31.713151	85	EXECUTED	9:7d93d602352a30c0c317e6a609b56599	createIndex indexName=IDX_EVENT_TIME, tableName=EVENT_ENTITY		\N	4.33.0	\N	\N	2569129629
map-remove-ri	keycloak	META-INF/jpa-changelog-11.0.0.xml	2026-10-21 07:52:31.739316	86	EXECUTED	9:71c5969e6cdd8d7b6f47cebc86d37627	dropForeignKeyConstraint baseTableName=REALM, constraintName=FK_TRAF444KK6QRKMS7N56AIWQ5Y; dropForeignKeyConstraint baseTableName=KEYCLOAK_ROLE, constraintName=FK_KJHO5LE2C0RAL09FL8CM9WFW9		\N	4.33.0	\N	\N	2569129629
map-remove-ri	keycloak	META-INF/jpa-changelog-12.0.0.xml	2026-10-21 07:52:31.767364	87	EXECUTED	9:a9ba7d47f065f041b7da856a81762021	dropForeignKeyConstraint baseTableName=REALM_DEFAULT_GROUPS, constraintName=FK_DEF_GROUPS_GROUP; dropForeignKeyConstraint baseTableName=REALM_DEFAULT_ROLES, constraintName=FK_H4WPD7W4HSOOLNI3H0SW7BTJE; dropForeignKeyConstraint baseTableName=CLIENT...		\N	4.33.0	\N	\N	2569129629
12.1.0-add-realm-localization-table	keycloak	META-INF/jpa-changelog-12.0.0.xml	2026-10-21 07:52:31.787211	88	EXECUTED	9:fffabce2bc01e1a8f5110d5278500065	createTable tableName=REALM_LOCALIZATIONS; addPrimaryKey tableName=REALM_LOCALIZATIONS		\N	4.33.0	\N	\N	2569129629
default-roles	keycloak	META-INF/jpa-changelog-13.0.0.xml	2026-10-21 07:52:31.806107	89	EXECUTED	9:fa8a5b5445e3857f4b010bafb5009957	addColumn tableName=REALM; customChange		\N	4.33.0	\N	\N	2569129629
default-roles-cleanup	keycloak	META-INF/jpa-changelog-13.0.0.xml	2026-10-21 07:52:31.822929	90	EXECUTED	9:67ac3241df9a8582d591c5ed87125f39	dropTable tableName=REALM_DEFAULT_ROLES; dropTable tableName=CLIENT_DEFAULT_ROLES		\N	4.33.0	\N	\N	2569129629
13.0.0-KEYCLOAK-16844	keycloak	META-INF/jpa-changelog-13.0.0.xml	2026-10-21 07:52:31.928834	91	EXECUTED	9:ad1194d66c937e3ffc82386c050ba089	createIndex indexName=IDX_OFFLINE_USS_PRELOAD, tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
map-remove-ri-13.0.0	keycloak	META-INF/jpa-changelog-13.0.0.xml	2026-10-21 07:52:31.956936	92	EXECUTED	9:d9be619d94af5a2f5d07b9f003543b91	dropForeignKeyConstraint baseTableName=DEFAULT_CLIENT_SCOPE, constraintName=FK_R_DEF_CLI_SCOPE_SCOPE; dropForeignKeyConstraint baseTableName=CLIENT_SCOPE_CLIENT, constraintName=FK_C_CLI_SCOPE_SCOPE; dropForeignKeyConstraint baseTableName=CLIENT_SC...		\N	4.33.0	\N	\N	2569129629
13.0.0-KEYCLOAK-17992-drop-constraints	keycloak	META-INF/jpa-changelog-13.0.0.xml	2026-10-21 07:52:31.962471	93	MARK_RAN	9:544d201116a0fcc5a5da0925fbbc3bde	dropPrimaryKey constraintName=C_CLI_SCOPE_BIND, tableName=CLIENT_SCOPE_CLIENT; dropIndex indexName=IDX_CLSCOPE_CL, tableName=CLIENT_SCOPE_CLIENT; dropIndex indexName=IDX_CL_CLSCOPE, tableName=CLIENT_SCOPE_CLIENT		\N	4.33.0	\N	\N	2569129629
13.0.0-increase-column-size-federated	keycloak	META-INF/jpa-changelog-13.0.0.xml	2026-10-21 07:52:31.986674	94	EXECUTED	9:43c0c1055b6761b4b3e89de76d612ccf	modifyDataType columnName=CLIENT_ID, tableName=CLIENT_SCOPE_CLIENT; modifyDataType columnName=SCOPE_ID, tableName=CLIENT_SCOPE_CLIENT		\N	4.33.0	\N	\N	2569129629
13.0.0-KEYCLOAK-17992-recreate-constraints	keycloak	META-INF/jpa-changelog-13.0.0.xml	2026-10-21 07:52:31.992656	95	MARK_RAN	9:8bd711fd0330f4fe980494ca43ab1139	addNotNullConstraint columnName=CLIENT_ID, tableName=CLIENT_SCOPE_CLIENT; addNotNullConstraint columnName=SCOPE_ID, tableName=CLIENT_SCOPE_CLIENT; addPrimaryKey constraintName=C_CLI_SCOPE_BIND, tableName=CLIENT_SCOPE_CLIENT; createIndex indexName=...		\N	4.33.0	\N	\N	2569129629
json-string-accomodation-fixed	keycloak	META-INF/jpa-changelog-13.0.0.xml	2026-10-21 07:52:32.020744	96	EXECUTED	9:e07d2bc0970c348bb06fb63b1f82ddbf	addColumn tableName=REALM_ATTRIBUTE; update tableName=REALM_ATTRIBUTE; dropColumn columnName=VALUE, tableName=REALM_ATTRIBUTE; renameColumn newColumnName=VALUE, oldColumnName=VALUE_NEW, tableName=REALM_ATTRIBUTE		\N	4.33.0	\N	\N	2569129629
14.0.0-KEYCLOAK-11019	keycloak	META-INF/jpa-changelog-14.0.0.xml	2026-10-21 07:52:32.335518	97	EXECUTED	9:24fb8611e97f29989bea412aa38d12b7	createIndex indexName=IDX_OFFLINE_CSS_PRELOAD, tableName=OFFLINE_CLIENT_SESSION; createIndex indexName=IDX_OFFLINE_USS_BY_USER, tableName=OFFLINE_USER_SESSION; createIndex indexName=IDX_OFFLINE_USS_BY_USERSESS, tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
14.0.0-KEYCLOAK-18286	keycloak	META-INF/jpa-changelog-14.0.0.xml	2026-10-21 07:52:32.339346	98	MARK_RAN	9:259f89014ce2506ee84740cbf7163aa7	createIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.33.0	\N	\N	2569129629
14.0.0-KEYCLOAK-18286-revert	keycloak	META-INF/jpa-changelog-14.0.0.xml	2026-10-21 07:52:32.372551	99	MARK_RAN	9:04baaf56c116ed19951cbc2cca584022	dropIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.33.0	\N	\N	2569129629
14.0.0-KEYCLOAK-18286-supported-dbs	keycloak	META-INF/jpa-changelog-14.0.0.xml	2026-10-21 07:52:32.491712	100	EXECUTED	9:60ca84a0f8c94ec8c3504a5a3bc88ee8	createIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.33.0	\N	\N	2569129629
14.0.0-KEYCLOAK-18286-unsupported-dbs	keycloak	META-INF/jpa-changelog-14.0.0.xml	2026-10-21 07:52:32.497776	101	MARK_RAN	9:d3d977031d431db16e2c181ce49d73e9	createIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.33.0	\N	\N	2569129629
KEYCLOAK-17267-add-index-to-user-attributes	keycloak	META-INF/jpa-changelog-14.0.0.xml	2026-10-21 07:52:32.642488	102	EXECUTED	9:0b305d8d1277f3a89a0a53a659ad274c	createIndex indexName=IDX_USER_ATTRIBUTE_NAME, tableName=USER_ATTRIBUTE		\N	4.33.0	\N	\N	2569129629
KEYCLOAK-18146-add-saml-art-binding-identifier	keycloak	META-INF/jpa-changelog-14.0.0.xml	2026-10-21 07:52:32.658852	103	EXECUTED	9:2c374ad2cdfe20e2905a84c8fac48460	customChange		\N	4.33.0	\N	\N	2569129629
15.0.0-KEYCLOAK-18467	keycloak	META-INF/jpa-changelog-15.0.0.xml	2026-10-21 07:52:32.678596	104	EXECUTED	9:47a760639ac597360a8219f5b768b4de	addColumn tableName=REALM_LOCALIZATIONS; update tableName=REALM_LOCALIZATIONS; dropColumn columnName=TEXTS, tableName=REALM_LOCALIZATIONS; renameColumn newColumnName=TEXTS, oldColumnName=TEXTS_NEW, tableName=REALM_LOCALIZATIONS; addNotNullConstrai...		\N	4.33.0	\N	\N	2569129629
17.0.0-9562	keycloak	META-INF/jpa-changelog-17.0.0.xml	2026-10-21 07:52:32.794344	105	EXECUTED	9:a6272f0576727dd8cad2522335f5d99e	createIndex indexName=IDX_USER_SERVICE_ACCOUNT, tableName=USER_ENTITY		\N	4.33.0	\N	\N	2569129629
18.0.0-10625-IDX_ADMIN_EVENT_TIME	keycloak	META-INF/jpa-changelog-18.0.0.xml	2026-10-21 07:52:32.924847	106	EXECUTED	9:015479dbd691d9cc8669282f4828c41d	createIndex indexName=IDX_ADMIN_EVENT_TIME, tableName=ADMIN_EVENT_ENTITY		\N	4.33.0	\N	\N	2569129629
18.0.15-30992-index-consent	keycloak	META-INF/jpa-changelog-18.0.15.xml	2026-10-21 07:52:33.080693	107	EXECUTED	9:80071ede7a05604b1f4906f3bf3b00f0	createIndex indexName=IDX_USCONSENT_SCOPE_ID, tableName=USER_CONSENT_CLIENT_SCOPE		\N	4.33.0	\N	\N	2569129629
19.0.0-10135	keycloak	META-INF/jpa-changelog-19.0.0.xml	2026-10-21 07:52:33.100089	108	EXECUTED	9:9518e495fdd22f78ad6425cc30630221	customChange		\N	4.33.0	\N	\N	2569129629
20.0.0-12964-supported-dbs	keycloak	META-INF/jpa-changelog-20.0.0.xml	2026-10-21 07:52:33.211272	109	EXECUTED	9:e5f243877199fd96bcc842f27a1656ac	createIndex indexName=IDX_GROUP_ATT_BY_NAME_VALUE, tableName=GROUP_ATTRIBUTE		\N	4.33.0	\N	\N	2569129629
20.0.0-12964-supported-dbs-edb-migration	keycloak	META-INF/jpa-changelog-20.0.0.xml	2026-10-21 07:52:33.398144	110	EXECUTED	9:a6b18a8e38062df5793edbe064f4aecd	dropIndex indexName=IDX_GROUP_ATT_BY_NAME_VALUE, tableName=GROUP_ATTRIBUTE; createIndex indexName=IDX_GROUP_ATT_BY_NAME_VALUE, tableName=GROUP_ATTRIBUTE		\N	4.33.0	\N	\N	2569129629
20.0.0-12964-unsupported-dbs	keycloak	META-INF/jpa-changelog-20.0.0.xml	2026-10-21 07:52:33.404075	111	MARK_RAN	9:1a6fcaa85e20bdeae0a9ce49b41946a5	createIndex indexName=IDX_GROUP_ATT_BY_NAME_VALUE, tableName=GROUP_ATTRIBUTE		\N	4.33.0	\N	\N	2569129629
client-attributes-string-accomodation-fixed-pre-drop-index	keycloak	META-INF/jpa-changelog-20.0.0.xml	2026-10-21 07:52:33.427119	112	EXECUTED	9:04baaf56c116ed19951cbc2cca584022	dropIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.33.0	\N	\N	2569129629
client-attributes-string-accomodation-fixed	keycloak	META-INF/jpa-changelog-20.0.0.xml	2026-10-21 07:52:33.451293	113	EXECUTED	9:3f332e13e90739ed0c35b0b25b7822ca	addColumn tableName=CLIENT_ATTRIBUTES; update tableName=CLIENT_ATTRIBUTES; dropColumn columnName=VALUE, tableName=CLIENT_ATTRIBUTES; renameColumn newColumnName=VALUE, oldColumnName=VALUE_NEW, tableName=CLIENT_ATTRIBUTES		\N	4.33.0	\N	\N	2569129629
client-attributes-string-accomodation-fixed-post-create-index	keycloak	META-INF/jpa-changelog-20.0.0.xml	2026-10-21 07:52:33.45549	114	MARK_RAN	9:bd2bd0fc7768cf0845ac96a8786fa735	createIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.33.0	\N	\N	2569129629
21.0.2-17277	keycloak	META-INF/jpa-changelog-21.0.2.xml	2026-10-21 07:52:33.47344	115	EXECUTED	9:7ee1f7a3fb8f5588f171fb9a6ab623c0	customChange		\N	4.33.0	\N	\N	2569129629
21.1.0-19404	keycloak	META-INF/jpa-changelog-21.1.0.xml	2026-10-21 07:52:33.518229	116	EXECUTED	9:3d7e830b52f33676b9d64f7f2b2ea634	modifyDataType columnName=DECISION_STRATEGY, tableName=RESOURCE_SERVER_POLICY; modifyDataType columnName=LOGIC, tableName=RESOURCE_SERVER_POLICY; modifyDataType columnName=POLICY_ENFORCE_MODE, tableName=RESOURCE_SERVER		\N	4.33.0	\N	\N	2569129629
21.1.0-19404-2	keycloak	META-INF/jpa-changelog-21.1.0.xml	2026-10-21 07:52:33.525635	117	MARK_RAN	9:627d032e3ef2c06c0e1f73d2ae25c26c	addColumn tableName=RESOURCE_SERVER_POLICY; update tableName=RESOURCE_SERVER_POLICY; dropColumn columnName=DECISION_STRATEGY, tableName=RESOURCE_SERVER_POLICY; renameColumn newColumnName=DECISION_STRATEGY, oldColumnName=DECISION_STRATEGY_NEW, tabl...		\N	4.33.0	\N	\N	2569129629
22.0.0-17484-updated	keycloak	META-INF/jpa-changelog-22.0.0.xml	2026-10-21 07:52:33.546588	118	EXECUTED	9:90af0bfd30cafc17b9f4d6eccd92b8b3	customChange		\N	4.33.0	\N	\N	2569129629
23.0.0-12062	keycloak	META-INF/jpa-changelog-23.0.0.xml	2026-10-21 07:52:33.569977	120	EXECUTED	9:2168fbe728fec46ae9baf15bf80927b8	addColumn tableName=COMPONENT_CONFIG; update tableName=COMPONENT_CONFIG; dropColumn columnName=VALUE, tableName=COMPONENT_CONFIG; renameColumn newColumnName=VALUE, oldColumnName=VALUE_NEW, tableName=COMPONENT_CONFIG		\N	4.33.0	\N	\N	2569129629
23.0.0-17258	keycloak	META-INF/jpa-changelog-23.0.0.xml	2026-10-21 07:52:33.58	121	EXECUTED	9:36506d679a83bbfda85a27ea1864dca8	addColumn tableName=EVENT_ENTITY		\N	4.33.0	\N	\N	2569129629
24.0.0-9758	keycloak	META-INF/jpa-changelog-24.0.0.xml	2026-10-21 07:52:34.076125	122	EXECUTED	9:502c557a5189f600f0f445a9b49ebbce	addColumn tableName=USER_ATTRIBUTE; addColumn tableName=FED_USER_ATTRIBUTE; createIndex indexName=USER_ATTR_LONG_VALUES, tableName=USER_ATTRIBUTE; createIndex indexName=FED_USER_ATTR_LONG_VALUES, tableName=FED_USER_ATTRIBUTE; createIndex indexName...		\N	4.33.0	\N	\N	2569129629
24.0.0-9758-2	keycloak	META-INF/jpa-changelog-24.0.0.xml	2026-10-21 07:52:34.094361	123	EXECUTED	9:bf0fdee10afdf597a987adbf291db7b2	customChange		\N	4.33.0	\N	\N	2569129629
24.0.0-26618-drop-index-if-present	keycloak	META-INF/jpa-changelog-24.0.0.xml	2026-10-21 07:52:34.116365	124	MARK_RAN	9:04baaf56c116ed19951cbc2cca584022	dropIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.33.0	\N	\N	2569129629
24.0.0-26618-reindex	keycloak	META-INF/jpa-changelog-24.0.0.xml	2026-10-21 07:52:34.301056	125	EXECUTED	9:08707c0f0db1cef6b352db03a60edc7f	createIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.33.0	\N	\N	2569129629
24.0.0-26618-edb-migration	keycloak	META-INF/jpa-changelog-24.0.0.xml	2026-10-21 07:52:34.472858	126	EXECUTED	9:2f684b29d414cd47efe3a3599f390741	dropIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES; createIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.33.0	\N	\N	2569129629
24.0.2-27228	keycloak	META-INF/jpa-changelog-24.0.2.xml	2026-10-21 07:52:34.49045	127	EXECUTED	9:eaee11f6b8aa25d2cc6a84fb86fc6238	customChange		\N	4.33.0	\N	\N	2569129629
24.0.2-27967-drop-index-if-present	keycloak	META-INF/jpa-changelog-24.0.2.xml	2026-10-21 07:52:34.495671	128	MARK_RAN	9:04baaf56c116ed19951cbc2cca584022	dropIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.33.0	\N	\N	2569129629
24.0.2-27967-reindex	keycloak	META-INF/jpa-changelog-24.0.2.xml	2026-10-21 07:52:34.503622	129	MARK_RAN	9:d3d977031d431db16e2c181ce49d73e9	createIndex indexName=IDX_CLIENT_ATT_BY_NAME_VALUE, tableName=CLIENT_ATTRIBUTES		\N	4.33.0	\N	\N	2569129629
25.0.0-28265-tables	keycloak	META-INF/jpa-changelog-25.0.0.xml	2026-10-21 07:52:34.524012	130	EXECUTED	9:deda2df035df23388af95bbd36c17cef	addColumn tableName=OFFLINE_USER_SESSION; addColumn tableName=OFFLINE_CLIENT_SESSION		\N	4.33.0	\N	\N	2569129629
25.0.0-28265-index-creation	keycloak	META-INF/jpa-changelog-25.0.0.xml	2026-10-21 07:52:34.628005	131	EXECUTED	9:3e96709818458ae49f3c679ae58d263a	createIndex indexName=IDX_OFFLINE_USS_BY_LAST_SESSION_REFRESH, tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
25.0.0-28265-index-cleanup-uss-createdon	keycloak	META-INF/jpa-changelog-25.0.0.xml	2026-10-21 07:52:34.649412	132	EXECUTED	9:78ab4fc129ed5e8265dbcc3485fba92f	dropIndex indexName=IDX_OFFLINE_USS_CREATEDON, tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
25.0.0-28265-index-cleanup-uss-preload	keycloak	META-INF/jpa-changelog-25.0.0.xml	2026-10-21 07:52:34.675839	133	EXECUTED	9:de5f7c1f7e10994ed8b62e621d20eaab	dropIndex indexName=IDX_OFFLINE_USS_PRELOAD, tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
25.0.0-28265-index-cleanup-uss-by-usersess	keycloak	META-INF/jpa-changelog-25.0.0.xml	2026-10-21 07:52:34.710664	134	EXECUTED	9:6eee220d024e38e89c799417ec33667f	dropIndex indexName=IDX_OFFLINE_USS_BY_USERSESS, tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
25.0.0-28265-index-cleanup-css-preload	keycloak	META-INF/jpa-changelog-25.0.0.xml	2026-10-21 07:52:34.742581	135	EXECUTED	9:5411d2fb2891d3e8d63ddb55dfa3c0c9	dropIndex indexName=IDX_OFFLINE_CSS_PRELOAD, tableName=OFFLINE_CLIENT_SESSION		\N	4.33.0	\N	\N	2569129629
25.0.0-28265-index-2-mysql	keycloak	META-INF/jpa-changelog-25.0.0.xml	2026-10-21 07:52:34.749645	136	MARK_RAN	9:b7ef76036d3126bb83c2423bf4d449d6	createIndex indexName=IDX_OFFLINE_USS_BY_BROKER_SESSION_ID, tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
25.0.0-28265-index-2-not-mysql	keycloak	META-INF/jpa-changelog-25.0.0.xml	2026-10-21 07:52:34.881307	137	EXECUTED	9:23396cf51ab8bc1ae6f0cac7f9f6fcf7	createIndex indexName=IDX_OFFLINE_USS_BY_BROKER_SESSION_ID, tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
25.0.0-org	keycloak	META-INF/jpa-changelog-25.0.0.xml	2026-10-21 07:52:34.921151	138	EXECUTED	9:5c859965c2c9b9c72136c360649af157	createTable tableName=ORG; addUniqueConstraint constraintName=UK_ORG_NAME, tableName=ORG; addUniqueConstraint constraintName=UK_ORG_GROUP, tableName=ORG; createTable tableName=ORG_DOMAIN		\N	4.33.0	\N	\N	2569129629
unique-consentuser	keycloak	META-INF/jpa-changelog-25.0.0.xml	2026-10-21 07:52:34.953607	139	EXECUTED	9:5857626a2ea8767e9a6c66bf3a2cb32f	customChange; dropUniqueConstraint constraintName=UK_JKUWUVD56ONTGSUHOGM8UEWRT, tableName=USER_CONSENT; addUniqueConstraint constraintName=UK_LOCAL_CONSENT, tableName=USER_CONSENT; addUniqueConstraint constraintName=UK_EXTERNAL_CONSENT, tableName=...		\N	4.33.0	\N	\N	2569129629
unique-consentuser-edb-migration	keycloak	META-INF/jpa-changelog-25.0.0.xml	2026-10-21 07:52:34.982476	140	MARK_RAN	9:5857626a2ea8767e9a6c66bf3a2cb32f	customChange; dropUniqueConstraint constraintName=UK_JKUWUVD56ONTGSUHOGM8UEWRT, tableName=USER_CONSENT; addUniqueConstraint constraintName=UK_LOCAL_CONSENT, tableName=USER_CONSENT; addUniqueConstraint constraintName=UK_EXTERNAL_CONSENT, tableName=...		\N	4.33.0	\N	\N	2569129629
unique-consentuser-mysql	keycloak	META-INF/jpa-changelog-25.0.0.xml	2026-10-21 07:52:34.989711	141	MARK_RAN	9:b79478aad5adaa1bc428e31563f55e8e	customChange; dropUniqueConstraint constraintName=UK_JKUWUVD56ONTGSUHOGM8UEWRT, tableName=USER_CONSENT; addUniqueConstraint constraintName=UK_LOCAL_CONSENT, tableName=USER_CONSENT; addUniqueConstraint constraintName=UK_EXTERNAL_CONSENT, tableName=...		\N	4.33.0	\N	\N	2569129629
25.0.0-28861-index-creation	keycloak	META-INF/jpa-changelog-25.0.0.xml	2026-10-21 07:52:35.198661	142	EXECUTED	9:b9acb58ac958d9ada0fe12a5d4794ab1	createIndex indexName=IDX_PERM_TICKET_REQUESTER, tableName=RESOURCE_SERVER_PERM_TICKET; createIndex indexName=IDX_PERM_TICKET_OWNER, tableName=RESOURCE_SERVER_PERM_TICKET		\N	4.33.0	\N	\N	2569129629
26.0.0-org-alias	keycloak	META-INF/jpa-changelog-26.0.0.xml	2026-10-21 07:52:35.219	143	EXECUTED	9:6ef7d63e4412b3c2d66ed179159886a4	addColumn tableName=ORG; update tableName=ORG; addNotNullConstraint columnName=ALIAS, tableName=ORG; addUniqueConstraint constraintName=UK_ORG_ALIAS, tableName=ORG		\N	4.33.0	\N	\N	2569129629
26.0.0-org-group	keycloak	META-INF/jpa-changelog-26.0.0.xml	2026-10-21 07:52:35.254649	144	EXECUTED	9:da8e8087d80ef2ace4f89d8c5b9ca223	addColumn tableName=KEYCLOAK_GROUP; update tableName=KEYCLOAK_GROUP; addNotNullConstraint columnName=TYPE, tableName=KEYCLOAK_GROUP; customChange		\N	4.33.0	\N	\N	2569129629
26.0.0-org-indexes	keycloak	META-INF/jpa-changelog-26.0.0.xml	2026-10-21 07:52:35.401001	145	EXECUTED	9:79b05dcd610a8c7f25ec05135eec0857	createIndex indexName=IDX_ORG_DOMAIN_ORG_ID, tableName=ORG_DOMAIN		\N	4.33.0	\N	\N	2569129629
26.0.0-org-group-membership	keycloak	META-INF/jpa-changelog-26.0.0.xml	2026-10-21 07:52:35.420035	146	EXECUTED	9:a6ace2ce583a421d89b01ba2a28dc2d4	addColumn tableName=USER_GROUP_MEMBERSHIP; update tableName=USER_GROUP_MEMBERSHIP; addNotNullConstraint columnName=MEMBERSHIP_TYPE, tableName=USER_GROUP_MEMBERSHIP		\N	4.33.0	\N	\N	2569129629
31296-persist-revoked-access-tokens	keycloak	META-INF/jpa-changelog-26.0.0.xml	2026-10-21 07:52:35.440649	147	EXECUTED	9:64ef94489d42a358e8304b0e245f0ed4	createTable tableName=REVOKED_TOKEN; addPrimaryKey constraintName=CONSTRAINT_RT, tableName=REVOKED_TOKEN		\N	4.33.0	\N	\N	2569129629
31725-index-persist-revoked-access-tokens	keycloak	META-INF/jpa-changelog-26.0.0.xml	2026-10-21 07:52:35.589893	148	EXECUTED	9:b994246ec2bf7c94da881e1d28782c7b	createIndex indexName=IDX_REV_TOKEN_ON_EXPIRE, tableName=REVOKED_TOKEN		\N	4.33.0	\N	\N	2569129629
26.0.0-idps-for-login	keycloak	META-INF/jpa-changelog-26.0.0.xml	2026-10-21 07:52:35.920472	149	EXECUTED	9:51f5fffadf986983d4bd59582c6c1604	addColumn tableName=IDENTITY_PROVIDER; createIndex indexName=IDX_IDP_REALM_ORG, tableName=IDENTITY_PROVIDER; createIndex indexName=IDX_IDP_FOR_LOGIN, tableName=IDENTITY_PROVIDER; customChange		\N	4.33.0	\N	\N	2569129629
26.0.0-32583-drop-redundant-index-on-client-session	keycloak	META-INF/jpa-changelog-26.0.0.xml	2026-10-21 07:52:35.950237	150	EXECUTED	9:24972d83bf27317a055d234187bb4af9	dropIndex indexName=IDX_US_SESS_ID_ON_CL_SESS, tableName=OFFLINE_CLIENT_SESSION		\N	4.33.0	\N	\N	2569129629
26.0.0.32582-remove-tables-user-session-user-session-note-and-client-session	keycloak	META-INF/jpa-changelog-26.0.0.xml	2026-10-21 07:52:36.006814	151	EXECUTED	9:febdc0f47f2ed241c59e60f58c3ceea5	dropTable tableName=CLIENT_SESSION_ROLE; dropTable tableName=CLIENT_SESSION_NOTE; dropTable tableName=CLIENT_SESSION_PROT_MAPPER; dropTable tableName=CLIENT_SESSION_AUTH_STATUS; dropTable tableName=CLIENT_USER_SESSION_NOTE; dropTable tableName=CLI...		\N	4.33.0	\N	\N	2569129629
26.0.0-33201-org-redirect-url	keycloak	META-INF/jpa-changelog-26.0.0.xml	2026-10-21 07:52:36.021354	152	EXECUTED	9:4d0e22b0ac68ebe9794fa9cb752ea660	addColumn tableName=ORG		\N	4.33.0	\N	\N	2569129629
29399-jdbc-ping-default	keycloak	META-INF/jpa-changelog-26.1.0.xml	2026-10-21 07:52:36.05	153	EXECUTED	9:007dbe99d7203fca403b89d4edfdf21e	createTable tableName=JGROUPS_PING; addPrimaryKey constraintName=CONSTRAINT_JGROUPS_PING, tableName=JGROUPS_PING		\N	4.33.0	\N	\N	2569129629
26.1.0-34013	keycloak	META-INF/jpa-changelog-26.1.0.xml	2026-10-21 07:52:36.074541	154	EXECUTED	9:e6b686a15759aef99a6d758a5c4c6a26	addColumn tableName=ADMIN_EVENT_ENTITY		\N	4.33.0	\N	\N	2569129629
26.1.0-34380	keycloak	META-INF/jpa-changelog-26.1.0.xml	2026-10-21 07:52:36.092341	155	EXECUTED	9:ac8b9edb7c2b6c17a1c7a11fcf5ccf01	dropTable tableName=USERNAME_LOGIN_FAILURE		\N	4.33.0	\N	\N	2569129629
26.2.0-36750	keycloak	META-INF/jpa-changelog-26.2.0.xml	2026-10-21 07:52:36.117858	156	EXECUTED	9:b49ce951c22f7eb16480ff085640a33a	createTable tableName=SERVER_CONFIG		\N	4.33.0	\N	\N	2569129629
26.2.0-26106	keycloak	META-INF/jpa-changelog-26.2.0.xml	2026-10-21 07:52:36.132859	157	EXECUTED	9:b5877d5dab7d10ff3a9d209d7beb6680	addColumn tableName=CREDENTIAL		\N	4.33.0	\N	\N	2569129629
26.2.6-39866-duplicate	keycloak	META-INF/jpa-changelog-26.2.6.xml	2026-10-21 07:52:36.153879	158	EXECUTED	9:1dc67ccee24f30331db2cba4f372e40e	customChange		\N	4.33.0	\N	\N	2569129629
26.2.6-39866-uk	keycloak	META-INF/jpa-changelog-26.2.6.xml	2026-10-21 07:52:36.169151	159	EXECUTED	9:b70b76f47210cf0a5f4ef0e219eac7cd	addUniqueConstraint constraintName=UK_MIGRATION_VERSION, tableName=MIGRATION_MODEL		\N	4.33.0	\N	\N	2569129629
26.2.6-40088-duplicate	keycloak	META-INF/jpa-changelog-26.2.6.xml	2026-10-21 07:52:36.189034	160	EXECUTED	9:cc7e02ed69ab31979afb1982f9670e8f	customChange		\N	4.33.0	\N	\N	2569129629
26.2.6-40088-uk	keycloak	META-INF/jpa-changelog-26.2.6.xml	2026-10-21 07:52:36.204749	161	EXECUTED	9:5bb848128da7bc4595cc507383325241	addUniqueConstraint constraintName=UK_MIGRATION_UPDATE_TIME, tableName=MIGRATION_MODEL		\N	4.33.0	\N	\N	2569129629
26.3.0-groups-description	keycloak	META-INF/jpa-changelog-26.3.0.xml	2026-10-21 07:52:36.22178	162	EXECUTED	9:e1a3c05574326fb5b246b73b9a4c4d49	addColumn tableName=KEYCLOAK_GROUP		\N	4.33.0	\N	\N	2569129629
26.4.0-40933-saml-encryption-attributes	keycloak	META-INF/jpa-changelog-26.4.0.xml	2026-10-21 07:52:36.241671	163	EXECUTED	9:7e9eaba362ca105efdda202303a4fe49	customChange		\N	4.33.0	\N	\N	2569129629
26.4.0-51321	keycloak	META-INF/jpa-changelog-26.4.0.xml	2026-10-21 07:52:36.386355	164	EXECUTED	9:34bab2bc56f75ffd7e347c580874e306	createIndex indexName=IDX_EVENT_ENTITY_USER_ID_TYPE, tableName=EVENT_ENTITY		\N	4.33.0	\N	\N	2569129629
40343-workflow-state-table	keycloak	META-INF/jpa-changelog-26.4.0.xml	2026-10-21 07:52:36.675227	165	EXECUTED	9:ed3ab4723ceed210e5b5e60ac4562106	createTable tableName=WORKFLOW_STATE; addPrimaryKey constraintName=PK_WORKFLOW_STATE, tableName=WORKFLOW_STATE; addUniqueConstraint constraintName=UQ_WORKFLOW_RESOURCE, tableName=WORKFLOW_STATE; createIndex indexName=IDX_WORKFLOW_STATE_STEP, table...		\N	4.33.0	\N	\N	2569129629
26.5.0-index-offline-css-by-client	keycloak	META-INF/jpa-changelog-26.5.0.xml	2026-10-21 07:52:36.843292	166	EXECUTED	9:383e981ce95d16e32af757b7998820f7	createIndex indexName=IDX_OFFLINE_CSS_BY_CLIENT, tableName=OFFLINE_CLIENT_SESSION		\N	4.33.0	\N	\N	2569129629
26.5.0-index-offline-css-by-client-storage-provider	keycloak	META-INF/jpa-changelog-26.5.0.xml	2026-10-21 07:52:36.984163	167	EXECUTED	9:f5bc200e6fa7d7e483854dee535ca425	createIndex indexName=IDX_OFFLINE_CSS_BY_CLIENT_STORAGE_PROVIDER, tableName=OFFLINE_CLIENT_SESSION		\N	4.33.0	\N	\N	2569129629
26.5.0-idp-config-allow-null-fixed-drop-mssql-index	keycloak	META-INF/jpa-changelog-26.5.0.xml	2026-10-21 07:52:36.988948	168	MARK_RAN	9:50c51d2c98cd1d624eb1c485c3cf1f75	dropIndex indexName=IDX_IDP_FOR_LOGIN, tableName=IDENTITY_PROVIDER		\N	4.33.0	\N	\N	2569129629
26.5.0-idp-config-allow-null	keycloak	META-INF/jpa-changelog-26.5.0.xml	2026-10-21 07:52:37.031126	169	EXECUTED	9:b667fb087874303b324c1af7fae4f606	dropDefaultValue columnName=TRUST_EMAIL, tableName=IDENTITY_PROVIDER; dropNotNullConstraint columnName=TRUST_EMAIL, tableName=IDENTITY_PROVIDER; dropNotNullConstraint columnName=STORE_TOKEN, tableName=IDENTITY_PROVIDER; dropDefaultValue columnName...		\N	4.33.0	\N	\N	2569129629
26.5.0-idp-config-allow-null-fixed-create-mssql-index	keycloak	META-INF/jpa-changelog-26.5.0.xml	2026-10-21 07:52:37.037465	170	MARK_RAN	9:dcbbb24c151c3b0b59f12fede23cc94d	createIndex indexName=IDX_IDP_FOR_LOGIN, tableName=IDENTITY_PROVIDER		\N	4.33.0	\N	\N	2569129629
26.5.0-remove-workflow-provider-id-column	keycloak	META-INF/jpa-changelog-26.5.0.xml	2026-10-21 07:52:37.234148	171	EXECUTED	9:d8eeb324484d45e946d03b953e168b21	dropIndex indexName=IDX_WORKFLOW_STATE_PROVIDER, tableName=WORKFLOW_STATE; createIndex indexName=IDX_WORKFLOW_STATE_PROVIDER, tableName=WORKFLOW_STATE; dropColumn columnName=WORKFLOW_PROVIDER_ID, tableName=WORKFLOW_STATE		\N	4.33.0	\N	\N	2569129629
26.5.0-add-remember-me	keycloak	META-INF/jpa-changelog-26.5.0.xml	2026-10-21 07:52:37.254392	172	EXECUTED	9:a7273ea8b21bd2f674c9c49141999f05	addColumn tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
26.5.0-add-sess-refresh-idx	keycloak	META-INF/jpa-changelog-26.5.0.xml	2026-10-21 07:52:37.411834	173	EXECUTED	9:ce49383d317ccbcd3434d1f21172b0b7	createIndex indexName=IDX_USER_SESSION_EXPIRATION_CREATED, tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
26.5.0-add-sess-create-idx	keycloak	META-INF/jpa-changelog-26.5.0.xml	2026-10-21 07:52:37.601717	174	EXECUTED	9:aaee09e23a4d8468fbc5c51b7b314c58	createIndex indexName=IDX_USER_SESSION_EXPIRATION_LAST_REFRESH, tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
26.5.0-drop-sess-refresh-idx	keycloak	META-INF/jpa-changelog-26.5.0.xml	2026-10-21 07:52:37.635777	175	EXECUTED	9:f0082210b6ccbbaf81287c27aa23753c	dropIndex indexName=IDX_OFFLINE_USS_BY_LAST_SESSION_REFRESH, tableName=OFFLINE_USER_SESSION		\N	4.33.0	\N	\N	2569129629
26.5.0-mysql-mariadb-default-charset-collation	keycloak	META-INF/jpa-changelog-26.5.0.xml	2026-10-21 07:52:37.641689	176	MARK_RAN	9:1b383fa60d2db0a8952b365e725f9d16	customChange		\N	4.33.0	\N	\N	2569129629
26.5.0-invitations-table-fixed2	keycloak	META-INF/jpa-changelog-26.5.0.xml	2026-10-21 07:52:38.189418	177	EXECUTED	9:322cb11fc03181903dcd67a54f8b3cf0	createTable tableName=ORG_INVITATION; addForeignKeyConstraint baseTableName=ORG_INVITATION, constraintName=FK_ORG_INVITATION_ORG, referencedTableName=ORG; createIndex indexName=IDX_ORG_INVITATION_ORG_ID, tableName=ORG_INVITATION; createIndex index...		\N	4.33.0	\N	\N	2569129629
26.6.0-45009-broker-link-user-id	keycloak	META-INF/jpa-changelog-26.6.0.xml	2026-10-21 07:52:38.332049	178	EXECUTED	9:05026bbbc8d2ead5afcbda2f5fdf3a2b	createIndex indexName=IDX_BROKER_LINK_USER_ID, tableName=BROKER_LINK		\N	4.33.0	\N	\N	2569129629
26.6.0-45009-broker-link-identity-provider	keycloak	META-INF/jpa-changelog-26.6.0.xml	2026-10-21 07:52:38.53169	179	EXECUTED	9:7d9a0253c9de7be754efef8bba4265bd	createIndex indexName=IDX_BROKER_LINK_IDENTITY_PROVIDER, tableName=BROKER_LINK		\N	4.33.0	\N	\N	2569129629
26.6.0-org-group-relationship	keycloak	META-INF/jpa-changelog-26.6.0.xml	2026-10-21 07:52:38.72231	180	EXECUTED	9:05685853fba030f53548ac6bf23245e3	addColumn tableName=KEYCLOAK_GROUP; addForeignKeyConstraint baseTableName=KEYCLOAK_GROUP, constraintName=FK_GROUP_ORGANIZATION, referencedTableName=ORG; createIndex indexName=IDX_GROUP_ORG_ID, tableName=KEYCLOAK_GROUP		\N	4.33.0	\N	\N	2569129629
26.6.0-44424-index-css-user-session-and-offline	keycloak	META-INF/jpa-changelog-26.6.0.xml	2026-10-21 07:52:38.912005	181	EXECUTED	9:a704d8598df241a3fd3cb91b6ab4b2d4	createIndex indexName=IDX_OFFLINE_CSS_BY_USER_SESSION_AND_OFFLINE, tableName=OFFLINE_CLIENT_SESSION		\N	4.33.0	\N	\N	2569129629
26.6.0-44424-create-realm-in-client-session	keycloak	META-INF/jpa-changelog-26.6.0.xml	2026-10-21 07:52:38.932546	182	EXECUTED	9:77dbbc72d943e98cfe472ba8cc56a31c	addColumn tableName=OFFLINE_CLIENT_SESSION		\N	4.33.0	\N	\N	2569129629
26.6.0-44424-set-realm-in-client-session	keycloak	META-INF/jpa-changelog-26.6.0.xml	2026-10-21 07:52:38.955255	183	EXECUTED	9:3964a3148d32a55ef81126e23cdf6721	customChange		\N	4.33.0	\N	\N	2569129629
26.6.0-44424-idx-css-realm-and-clients	keycloak	META-INF/jpa-changelog-26.6.0.xml	2026-10-21 07:52:39.208756	184	EXECUTED	9:a093877fff41185ac24103be80e00968	createIndex indexName=IDX_OFFLINE_CSS_BY_CLIENT_AND_REALM, tableName=OFFLINE_CLIENT_SESSION		\N	4.33.0	\N	\N	2569129629
26.6.0-add-last-modified-timestamp-user	keycloak	META-INF/jpa-changelog-26.6.0.xml	2026-10-21 07:52:39.23182	185	EXECUTED	9:8aa583d2cdd9e913dff42fecd626c560	addColumn tableName=USER_ENTITY		\N	4.33.0	\N	\N	2569129629
26.6.0-add-timestamps-group	keycloak	META-INF/jpa-changelog-26.6.0.xml	2026-10-21 07:52:39.254318	186	EXECUTED	9:4363d45dc25105a3fc5db9ff6936b0a9	addColumn tableName=KEYCLOAK_GROUP		\N	4.33.0	\N	\N	2569129629
26.6.0-43829-user-created-timestamp-index	keycloak	META-INF/jpa-changelog-26.6.0.xml	2026-10-21 07:52:39.397123	187	EXECUTED	9:f2531a49b8bb21a7a97966d88fd1a411	createIndex indexName=IDX_USER_CREATED_TIMESTAMP, tableName=USER_ENTITY		\N	4.33.0	\N	\N	2569129629
26.6.0-48716-create-mssql-idp-index	keycloak	META-INF/jpa-changelog-26.6.0.xml	2026-10-21 07:52:39.402751	188	MARK_RAN	9:dcbbb24c151c3b0b59f12fede23cc94d	createIndex indexName=IDX_IDP_FOR_LOGIN, tableName=IDENTITY_PROVIDER		\N	4.33.0	\N	\N	2569129629
26.7.0-jdbcping-timestamp	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:39.421328	189	EXECUTED	9:9a91f62e494bd013594e007b74d01638	addColumn tableName=JGROUPS_PING		\N	4.33.0	\N	\N	2569129629
26.7.0-45292-realm-display-name-add-column	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:39.440665	190	EXECUTED	9:1de8c7824ce4fd7c739db6195f42be21	addColumn tableName=REALM		\N	4.33.0	\N	\N	2569129629
26.7.0-45292-realm-display-name-migrate-data	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:39.462621	191	EXECUTED	9:293096bc554dd51428d1d9882f2de1dd	customChange		\N	4.33.0	\N	\N	2569129629
26.7.0-45292-realm-display-name-remove-attribute	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:39.475345	192	EXECUTED	9:a08357e3b0908c09d478e692cf82f865	delete tableName=REALM_ATTRIBUTE		\N	4.33.0	\N	\N	2569129629
26.7.0-verifiable-credential	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:39.515814	193	EXECUTED	9:68d8df23794085e79ba08b5046cba31d	createTable tableName=USER_VER_CREDENTIAL; addPrimaryKey constraintName=CONSTRAINT_VCRED_PM, tableName=USER_VER_CREDENTIAL; addForeignKeyConstraint baseTableName=USER_VER_CREDENTIAL, constraintName=FK_VCRED_USER, referencedTableName=USER_ENTITY; a...		\N	4.33.0	\N	\N	2569129629
26.7.0-federated-verifiable-credentials-1	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:39.67011	194	EXECUTED	9:49092fa73b1c2b3afca48d91b8111c65	createTable tableName=FED_USER_VER_CREDENTIAL; addUniqueConstraint constraintName=UK_FED_USER_VC, tableName=FED_USER_VER_CREDENTIAL; createIndex indexName=IDX_FED_USER_VC_REALM_USER, tableName=FED_USER_VER_CREDENTIAL		\N	4.33.0	\N	\N	2569129629
26.7.0-outbox	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:41.032566	195	EXECUTED	9:338b2743ca1be95f895d8f9b0cbe7b55	createTable tableName=OUTBOX_ENTRY; addUniqueConstraint constraintName=UC_OUTBOX_KIND_OWNER_CORRELATION, tableName=OUTBOX_ENTRY; createIndex indexName=IDX_OUTBOX_DRAIN, tableName=OUTBOX_ENTRY; createIndex indexName=IDX_OUTBOX_REALM, tableName=OUTB...		\N	4.33.0	\N	\N	2569129629
26.7.0-9686-dynamic-scopes-consent	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:41.079009	196	EXECUTED	9:fb689bc3ff64e174d6319014b38876f1	addColumn tableName=USER_CONSENT_CLIENT_SCOPE; dropPrimaryKey constraintName=CONSTRAINT_GRNTCSNT_CLSC_PM, tableName=USER_CONSENT_CLIENT_SCOPE; addPrimaryKey constraintName=CONSTRAINT_GRNTCSNT_CLSC_PM, tableName=USER_CONSENT_CLIENT_SCOPE; addColumn...		\N	4.33.0	\N	\N	2569129629
26.7.0-46204-issued-ver-credential-table	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:41.287454	197	EXECUTED	9:4918c6f68ba90ce417f1aaa031013168	createTable tableName=ISSUED_VER_CREDENTIAL; addPrimaryKey constraintName=PK_ISSUED_VER_CREDENTIAL, tableName=ISSUED_VER_CREDENTIAL; addForeignKeyConstraint baseTableName=ISSUED_VER_CREDENTIAL, constraintName=FK_ISSUED_VER_CREDENTIAL_USER, referen...		\N	4.33.0	\N	\N	2569129629
26.7.0-issued-ver-credential-expires-at-index	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:41.490438	198	EXECUTED	9:ab9e4c0c9f21d9217ffe52968a3cf732	createIndex indexName=IDX_ISSUED_VER_CREDENTIAL_EXPIRES_AT, tableName=ISSUED_VER_CREDENTIAL		\N	4.33.0	\N	\N	2569129629
26.7.0-issued-ver-credential-vc-id-index	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:41.648178	199	EXECUTED	9:1c9b18926e48b4b66d0341400bd13834	createIndex indexName=IDX_ISSUED_VER_CREDENTIAL_VC, tableName=ISSUED_VER_CREDENTIAL		\N	4.33.0	\N	\N	2569129629
26.7.0-federated-issued-ver-credential	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:42.292815	200	EXECUTED	9:3d610f5527879623a0d2362e64fa667f	createTable tableName=FED_ISSUED_VER_CREDENTIAL; addForeignKeyConstraint baseTableName=FED_ISSUED_VER_CREDENTIAL, constraintName=FK_FED_ISSUED_VC_VER_CRED, referencedTableName=FED_USER_VER_CREDENTIAL; createIndex indexName=IDX_FED_ISSUED_VC_USER, ...		\N	4.33.0	\N	\N	2569129629
26.7.0-persistent-auth-session-root-table	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:42.330358	201	EXECUTED	9:ad622d5eebdf468747a0d08d2367a68e	createTable tableName=ROOT_AUTH_SESSION		\N	4.33.0	\N	\N	2569129629
26.7.0-persistent-auth-session-root-index	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:42.829795	202	EXECUTED	9:3090cd11d2dfeb5df754f41c0ffa35d7	createIndex indexName=IDX_ROOT_AUTH_SESSION_REALM, tableName=ROOT_AUTH_SESSION		\N	4.33.0	\N	\N	2569129629
26.7.0-persistent-auth-session-table	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:42.882081	203	EXECUTED	9:609b8a172e43f617bb8920efd2b9ae5f	createTable tableName=AUTH_SESSION; addPrimaryKey constraintName=PK_AUTH_SESSION, tableName=AUTH_SESSION; addForeignKeyConstraint baseTableName=AUTH_SESSION, constraintName=FK_AUTH_SESSION_ROOT, referencedTableName=ROOT_AUTH_SESSION		\N	4.33.0	\N	\N	2569129629
26.7.0-single-use-object-table	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:42.911355	204	EXECUTED	9:22bc4eb8e456b3b7be2808e457a44cb7	createTable tableName=SINGLE_USE_OBJECT		\N	4.33.0	\N	\N	2569129629
26.7.0-single-use-object-index	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:43.077725	205	EXECUTED	9:b2ad66c013f48dc131ce109eface7fa5	createIndex indexName=IDX_SINGLE_USE_OBJ_EXPIRE, tableName=SINGLE_USE_OBJECT		\N	4.33.0	\N	\N	2569129629
26.7.0-login-failure-table	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:43.108442	206	EXECUTED	9:671b50f88904b24ceb02463dd2d0c045	createTable tableName=LOGIN_FAILURE; addPrimaryKey constraintName=PK_LOGIN_FAILURE, tableName=LOGIN_FAILURE		\N	4.33.0	\N	\N	2569129629
26.7.0-login-failure-index	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:43.207999	207	EXECUTED	9:f554afc6ad14784c99f6ad8811ac30ec	createIndex indexName=IDX_LOGIN_FAILURE_EXPIRE, tableName=LOGIN_FAILURE		\N	4.33.0	\N	\N	2569129629
26.7.0-add-timestamps-client	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:43.221093	208	EXECUTED	9:df5324c82398b446690b206c07649d40	addColumn tableName=CLIENT		\N	4.33.0	\N	\N	2569129629
26.7.0-add-last-modified-timestamp-client	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:43.234536	209	EXECUTED	9:bae67d2faa5438ee35adfbb20a53c3c6	addColumn tableName=CLIENT		\N	4.33.0	\N	\N	2569129629
26.7.0-cluster-event	keycloak	META-INF/jpa-changelog-26.7.0.xml	2026-10-21 07:52:43.339733	210	EXECUTED	9:556b201eb9c378fa05d5bf22ec9c8dcf	createTable tableName=CLUSTER_EVENT; addPrimaryKey constraintName=PK_CLUSTER_EVENT, tableName=CLUSTER_EVENT; createIndex indexName=IDX_CLUSTER_EVENT_TARGET, tableName=CLUSTER_EVENT		\N	4.33.0	\N	\N	2569129629
\.


--
-- Data for Name: databasechangeloglock; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.databasechangeloglock (id, locked, lockgranted, lockedby) FROM stdin;
1	f	\N	\N
1000	f	\N	\N
\.


--
-- Data for Name: default_client_scope; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.default_client_scope (realm_id, scope_id, default_scope) FROM stdin;
331e6113-4db4-4433-997e-09db1350e12a	b386def2-101f-42cc-af67-160605b0c1b2	f
331e6113-4db4-4433-997e-09db1350e12a	e405615b-e22c-44eb-80ae-84dff928cd7f	t
331e6113-4db4-4433-997e-09db1350e12a	be4015dd-3b59-4cfa-a3e4-9c0112a90d5d	t
331e6113-4db4-4433-997e-09db1350e12a	549bfb16-8cc0-4634-ae5b-f4073270b3e4	t
331e6113-4db4-4433-997e-09db1350e12a	b448fe6b-e8e6-4adc-9ff7-45628fcb4560	t
331e6113-4db4-4433-997e-09db1350e12a	f09699e1-d95e-4dae-8187-1b6380b82a40	t
331e6113-4db4-4433-997e-09db1350e12a	ee3ade41-39d1-441d-9922-f7dc73cd8f24	f
331e6113-4db4-4433-997e-09db1350e12a	2f0d6ac3-76de-4d40-9825-5db7a96054a2	f
331e6113-4db4-4433-997e-09db1350e12a	335a2bcc-3f75-4032-bd25-d368c817655d	t
331e6113-4db4-4433-997e-09db1350e12a	31bb7ee4-e3fa-4a1b-a242-eb86a98ea2c8	t
331e6113-4db4-4433-997e-09db1350e12a	6977c07d-a0b9-4661-9ab0-8b5dcc5df3ae	f
331e6113-4db4-4433-997e-09db1350e12a	ec99790c-0896-4e6b-962a-a4295e6ce499	t
331e6113-4db4-4433-997e-09db1350e12a	468ad7f4-9f9f-4b4b-be02-4305be58e7dd	t
331e6113-4db4-4433-997e-09db1350e12a	bb5bb9a1-ba1e-432a-a857-c6c0291b2c54	f
5928e5d4-c400-4150-9107-da98acace8cf	f9106c30-ad3c-448d-99bb-fc6fa0353cc7	f
5928e5d4-c400-4150-9107-da98acace8cf	e134ec31-7d01-464d-b16b-4a71984873a1	t
5928e5d4-c400-4150-9107-da98acace8cf	5dab62a2-1f8c-4803-8c32-44158a24ab0a	t
5928e5d4-c400-4150-9107-da98acace8cf	e8a13582-4580-44e2-ab5c-f8b0a8ce4b52	t
5928e5d4-c400-4150-9107-da98acace8cf	ffb9f715-58c7-4afe-89ed-98862944e1f5	t
5928e5d4-c400-4150-9107-da98acace8cf	e8ef943d-eef2-4d47-9710-d7105d4a9e80	t
5928e5d4-c400-4150-9107-da98acace8cf	32c939de-30ec-4a62-96c0-00847c91aacf	f
5928e5d4-c400-4150-9107-da98acace8cf	6b2b117d-a23d-4844-9cbe-821f02964cf7	f
5928e5d4-c400-4150-9107-da98acace8cf	5ebfdbc1-e201-418c-b5af-8e28d36bf4f8	t
5928e5d4-c400-4150-9107-da98acace8cf	e9472182-f327-442e-9c0b-4c7745ea2ae8	t
5928e5d4-c400-4150-9107-da98acace8cf	bd194148-647b-4081-bb24-5c760c78d0e2	f
5928e5d4-c400-4150-9107-da98acace8cf	53e24107-4a5b-4e1b-9c18-478e75199b39	t
5928e5d4-c400-4150-9107-da98acace8cf	c0da43db-fc02-412e-829f-3d06eb946b76	t
5928e5d4-c400-4150-9107-da98acace8cf	cc70a7eb-bb51-4244-966d-e495cfe0f2bd	f
\.


--
-- Data for Name: event_entity; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.event_entity (id, client_id, details_json, error, ip_address, realm_id, session_id, event_time, type, user_id, details_json_long_value) FROM stdin;
\.


--
-- Data for Name: fed_issued_ver_credential; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.fed_issued_ver_credential (id, user_id, realm_id, storage_provider_id, ver_credential_id, issued_at, expires_at, client_id, revision) FROM stdin;
\.


--
-- Data for Name: fed_user_attribute; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.fed_user_attribute (id, name, user_id, realm_id, storage_provider_id, value, long_value_hash, long_value_hash_lower_case, long_value) FROM stdin;
\.


--
-- Data for Name: fed_user_consent; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.fed_user_consent (id, client_id, user_id, realm_id, storage_provider_id, created_date, last_updated_date, client_storage_provider, external_client_id) FROM stdin;
\.


--
-- Data for Name: fed_user_consent_cl_scope; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.fed_user_consent_cl_scope (user_consent_id, scope_id, parameter) FROM stdin;
\.


--
-- Data for Name: fed_user_credential; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.fed_user_credential (id, salt, type, created_date, user_id, realm_id, storage_provider_id, user_label, secret_data, credential_data, priority) FROM stdin;
\.


--
-- Data for Name: fed_user_group_membership; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.fed_user_group_membership (group_id, user_id, realm_id, storage_provider_id) FROM stdin;
\.


--
-- Data for Name: fed_user_required_action; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.fed_user_required_action (required_action, user_id, realm_id, storage_provider_id) FROM stdin;
\.


--
-- Data for Name: fed_user_role_mapping; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.fed_user_role_mapping (role_id, user_id, realm_id, storage_provider_id) FROM stdin;
\.


--
-- Data for Name: fed_user_ver_credential; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.fed_user_ver_credential (id, user_id, realm_id, storage_provider_id, client_scope_id, revision, user_attributes, created_date, updated_date, version) FROM stdin;
\.


--
-- Data for Name: federated_identity; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.federated_identity (identity_provider, realm_id, federated_user_id, federated_username, token, user_id) FROM stdin;
\.


--
-- Data for Name: federated_user; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.federated_user (id, storage_provider_id, realm_id) FROM stdin;
\.


--
-- Data for Name: group_attribute; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.group_attribute (id, name, value, group_id) FROM stdin;
\.


--
-- Data for Name: group_role_mapping; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.group_role_mapping (role_id, group_id) FROM stdin;
\.


--
-- Data for Name: identity_provider; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.identity_provider (internal_id, enabled, provider_alias, provider_id, store_token, authenticate_by_default, realm_id, add_token_role, trust_email, first_broker_login_flow_id, post_broker_login_flow_id, provider_display_name, link_only, organization_id, hide_on_login) FROM stdin;
\.


--
-- Data for Name: identity_provider_config; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.identity_provider_config (identity_provider_id, value, name) FROM stdin;
\.


--
-- Data for Name: identity_provider_mapper; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.identity_provider_mapper (id, name, idp_alias, idp_mapper_name, realm_id) FROM stdin;
\.


--
-- Data for Name: idp_mapper_config; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.idp_mapper_config (idp_mapper_id, value, name) FROM stdin;
\.


--
-- Data for Name: issued_ver_credential; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.issued_ver_credential (id, user_id, ver_credential_id, issued_at, expires_at, client_id, revision) FROM stdin;
\.


--
-- Data for Name: jgroups_ping; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.jgroups_ping (address, name, cluster_name, ip, coord, last_update, coordinated_by) FROM stdin;
\.


--
-- Data for Name: keycloak_group; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.keycloak_group (id, name, parent_group, realm_id, type, description, org_id, created_timestamp, last_modified_timestamp) FROM stdin;
\.


--
-- Data for Name: keycloak_role; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.keycloak_role (id, client_realm_constraint, client_role, description, name, realm_id, client, realm) FROM stdin;
6cf9ef6c-622a-4974-a502-6f878870e46a	331e6113-4db4-4433-997e-09db1350e12a	f	${role_default-roles}	default-roles-master	331e6113-4db4-4433-997e-09db1350e12a	\N	\N
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	331e6113-4db4-4433-997e-09db1350e12a	f	${role_admin}	admin	331e6113-4db4-4433-997e-09db1350e12a	\N	\N
a380ad84-fdfa-4ccb-bcb5-ab574d29c072	331e6113-4db4-4433-997e-09db1350e12a	f	${role_create-realm}	create-realm	331e6113-4db4-4433-997e-09db1350e12a	\N	\N
dbcedcf7-33b4-4a21-9ff7-b0e7ce50ebff	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_create-client}	create-client	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
b48fd3c0-57eb-4369-aec5-a70d016e9986	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_view-realm}	view-realm	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
f1ac4b3a-f1ec-4f75-b990-dab190c5e9b4	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_view-users}	view-users	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
4354b90b-9164-4db2-8f4e-647c86099f18	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_view-clients}	view-clients	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
75bb6ec6-77eb-46e9-8ef6-44e45051bf68	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_view-events}	view-events	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
f25e0b6f-e43b-4339-adde-73c85ee643ba	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_view-identity-providers}	view-identity-providers	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
07f98a6a-d429-4c57-86f4-69615777cca2	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_view-authorization}	view-authorization	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
b9a246e6-2fc1-4f88-ad50-054a7daa49f5	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_view-organizations}	view-organizations	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
3a19712f-6a6f-472a-9af3-075280f76d1e	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_manage-realm}	manage-realm	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
af6f94a6-f00c-4f5e-9698-fd28abbf0203	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_manage-users}	manage-users	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
bf782661-f931-431c-9155-ac6e3b2de258	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_manage-clients}	manage-clients	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
773c4c39-a97c-4890-a07b-e90599e413d1	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_manage-events}	manage-events	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
eb9e2689-d5d8-4964-99ef-7485be99e128	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_manage-identity-providers}	manage-identity-providers	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
644e2703-adad-42f6-a9e2-ed6601dbcdc1	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_manage-authorization}	manage-authorization	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
7f019472-88cd-4ad4-be44-4e9793dcd48e	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_manage-organizations}	manage-organizations	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
ba8085d6-b032-4c48-8431-6ec73b37fc97	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_query-users}	query-users	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
d3d07e72-5ad1-4caa-a3b0-0445cfbdefbc	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_query-clients}	query-clients	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
4a6091d3-1240-4c0c-81f9-5a8c1278611f	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_query-realms}	query-realms	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
b36d4994-157f-4df3-9854-5b4f9f3c0a3d	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_query-groups}	query-groups	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
29ae07d6-982d-4365-9442-358587c50f3a	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_query-organizations}	query-organizations	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
1ee9d24a-9b6f-4b3d-9a62-d71b0f447176	02c5d277-7643-45c6-a008-1bba899b38ef	t	${role_view-profile}	view-profile	331e6113-4db4-4433-997e-09db1350e12a	02c5d277-7643-45c6-a008-1bba899b38ef	\N
0e3782ab-601b-42e1-ac5a-8666e6c7a872	02c5d277-7643-45c6-a008-1bba899b38ef	t	${role_manage-account}	manage-account	331e6113-4db4-4433-997e-09db1350e12a	02c5d277-7643-45c6-a008-1bba899b38ef	\N
b93f6df8-bb40-4f99-b183-35f633692751	02c5d277-7643-45c6-a008-1bba899b38ef	t	${role_manage-account-links}	manage-account-links	331e6113-4db4-4433-997e-09db1350e12a	02c5d277-7643-45c6-a008-1bba899b38ef	\N
e4061ee0-75c2-4087-b7b6-12d3c38e5787	02c5d277-7643-45c6-a008-1bba899b38ef	t	${role_view-applications}	view-applications	331e6113-4db4-4433-997e-09db1350e12a	02c5d277-7643-45c6-a008-1bba899b38ef	\N
c8c3eeb9-f43c-4997-85be-b3b82fc5d9da	02c5d277-7643-45c6-a008-1bba899b38ef	t	${role_view-consent}	view-consent	331e6113-4db4-4433-997e-09db1350e12a	02c5d277-7643-45c6-a008-1bba899b38ef	\N
d44b0920-a48e-4385-b3cd-ba65dd2c25fc	02c5d277-7643-45c6-a008-1bba899b38ef	t	${role_manage-consent}	manage-consent	331e6113-4db4-4433-997e-09db1350e12a	02c5d277-7643-45c6-a008-1bba899b38ef	\N
7437daf7-f05d-42ec-84e4-e9ea47029534	02c5d277-7643-45c6-a008-1bba899b38ef	t	${role_view-groups}	view-groups	331e6113-4db4-4433-997e-09db1350e12a	02c5d277-7643-45c6-a008-1bba899b38ef	\N
2bb0fb50-d928-4f3f-b030-4ab2fa465587	02c5d277-7643-45c6-a008-1bba899b38ef	t	${role_delete-account}	delete-account	331e6113-4db4-4433-997e-09db1350e12a	02c5d277-7643-45c6-a008-1bba899b38ef	\N
493efe0f-a863-4289-9a8e-da8a1be7f668	eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	t	${role_read-token}	read-token	331e6113-4db4-4433-997e-09db1350e12a	eb464c49-4f3d-4047-b8c3-b25c7e9d19bd	\N
0664e646-4f22-46a0-aeed-56039423812b	4caeb1d0-bc9d-4239-a764-0237ee150cec	t	${role_impersonation}	impersonation	331e6113-4db4-4433-997e-09db1350e12a	4caeb1d0-bc9d-4239-a764-0237ee150cec	\N
6c27b134-5f46-42ed-b519-f9c86c2f64bd	331e6113-4db4-4433-997e-09db1350e12a	f	${role_offline-access}	offline_access	331e6113-4db4-4433-997e-09db1350e12a	\N	\N
29769b02-d59f-408f-be28-433f2ef47b9a	331e6113-4db4-4433-997e-09db1350e12a	f	${role_uma_authorization}	uma_authorization	331e6113-4db4-4433-997e-09db1350e12a	\N	\N
28e26c46-098c-4b01-8576-0d5799ac35c4	5928e5d4-c400-4150-9107-da98acace8cf	f	${role_default-roles}	default-roles-erp-realm	5928e5d4-c400-4150-9107-da98acace8cf	\N	\N
4757c5dd-6689-4f7f-9301-556b5e4b6c4c	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_create-client}	create-client	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
57e02dd4-b3d4-45a5-b7ca-dc45b754e24e	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_view-realm}	view-realm	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
b13ff089-8df2-4f94-ac69-641994228d6c	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_view-users}	view-users	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
8dab97a1-8f55-46cc-aa38-d82433abd0fd	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_view-clients}	view-clients	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
fa9ccdd7-62d1-4d3f-be18-0a5a022de995	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_view-events}	view-events	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
5a5b207b-a126-49b9-af8a-e58c8b4deca1	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_view-identity-providers}	view-identity-providers	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
c0e61e8c-6ae5-4b5f-9c5c-c6d44abd4824	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_view-authorization}	view-authorization	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
250f7371-b0e8-4104-bc9e-0ff9e90cb22c	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_view-organizations}	view-organizations	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
f928a9c5-db68-4eeb-9ecd-535ddfe1cbdf	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_manage-realm}	manage-realm	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
09bc0318-fffe-40be-a0e5-d210d5965d0a	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_manage-users}	manage-users	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
0e4f4637-5678-4f43-be31-0bab824d5d61	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_manage-clients}	manage-clients	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
34c0f251-44ec-4152-b24f-af83c1288092	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_manage-events}	manage-events	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
83541d45-c642-45de-bbbb-ca33a6a8b79a	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_manage-identity-providers}	manage-identity-providers	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
1f725527-ac1d-467f-a764-d8e0d711d80d	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_manage-authorization}	manage-authorization	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
bfc6f86e-6f00-424c-94cb-0f08e09b2b1f	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_manage-organizations}	manage-organizations	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
a43ea015-bf0b-47ba-9376-66ebd05649e9	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_query-users}	query-users	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
668bad6e-205e-4db2-84ad-d95bb7d59ca8	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_query-clients}	query-clients	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
d2e7fa26-68a2-445f-ac32-8e4892c1eb06	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_query-realms}	query-realms	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
c690a900-4115-4aaa-bdb0-5ff0e53e9814	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_query-groups}	query-groups	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
277f80a5-3d1b-4a0f-b09d-32b9514fdf5c	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_query-organizations}	query-organizations	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
97ef20f0-018b-4b7a-90e0-9906bb036a9e	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_realm-admin}	realm-admin	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
a8106fab-5b5b-447d-926e-37f11f0feeb0	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_create-client}	create-client	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
4cea49bc-9cb4-4650-83e9-9a8b097a4679	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_view-realm}	view-realm	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
bb4d2ef9-1e42-4ca8-bf51-6b6e71ac9624	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_view-users}	view-users	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
476d9f21-9bbb-48f7-9f75-aa4901ea80fe	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_view-clients}	view-clients	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
7f818540-98d8-4017-aece-264f674d5aa2	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_view-events}	view-events	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
64bc1cf1-48e3-4068-aa0b-5e5712a8dfab	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_view-identity-providers}	view-identity-providers	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
66799bec-68ae-4665-b0db-e166d9b0cfb8	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_view-authorization}	view-authorization	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
9eb6a249-3911-46d3-825e-737d53397d23	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_view-organizations}	view-organizations	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
54823542-84d5-411c-a78f-d86ec7b31057	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_manage-realm}	manage-realm	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
935f5ae3-f230-4e73-b37d-60452cc33867	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_manage-users}	manage-users	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
2de2c0b9-a573-4b33-877d-1efe2d400a52	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_manage-clients}	manage-clients	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
8bae4033-a12a-4388-80eb-b064a9cf38d0	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_manage-events}	manage-events	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
a0c8b708-68ef-48ff-abdc-a76cf807d879	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_manage-identity-providers}	manage-identity-providers	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
228d41b4-b59b-4049-9021-c112d753807a	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_manage-authorization}	manage-authorization	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
d647696e-e53e-4039-84cc-5dcd11241f8e	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_manage-organizations}	manage-organizations	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
9f49c0ba-388c-4367-9244-8453e205c995	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_query-users}	query-users	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
4d092a0b-dc97-402f-a59a-32615baa88aa	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_query-clients}	query-clients	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
c573e8b0-5ec2-4f86-bab2-22674c666d83	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_query-realms}	query-realms	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
cd1e2b44-4726-4424-bcc4-0c43f7aca7aa	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_query-groups}	query-groups	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
2c6b549a-14f0-4a95-a180-caae6fef4b51	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_query-organizations}	query-organizations	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
5149e6e2-7f44-4c8f-bf73-dfe109e1169b	5acab47a-ebce-406b-aaea-a826b37a7a67	t	${role_view-profile}	view-profile	5928e5d4-c400-4150-9107-da98acace8cf	5acab47a-ebce-406b-aaea-a826b37a7a67	\N
9ff03eea-be92-48e4-a780-af4078238a0a	5acab47a-ebce-406b-aaea-a826b37a7a67	t	${role_manage-account}	manage-account	5928e5d4-c400-4150-9107-da98acace8cf	5acab47a-ebce-406b-aaea-a826b37a7a67	\N
85d0a6a8-004c-42de-8dc0-885131ffdd8b	5acab47a-ebce-406b-aaea-a826b37a7a67	t	${role_manage-account-links}	manage-account-links	5928e5d4-c400-4150-9107-da98acace8cf	5acab47a-ebce-406b-aaea-a826b37a7a67	\N
501a5f08-ef19-4c3a-89e9-d85b9ab29546	5acab47a-ebce-406b-aaea-a826b37a7a67	t	${role_view-applications}	view-applications	5928e5d4-c400-4150-9107-da98acace8cf	5acab47a-ebce-406b-aaea-a826b37a7a67	\N
5efe3d6e-8bf8-484e-8685-284026ebf2ab	5acab47a-ebce-406b-aaea-a826b37a7a67	t	${role_view-consent}	view-consent	5928e5d4-c400-4150-9107-da98acace8cf	5acab47a-ebce-406b-aaea-a826b37a7a67	\N
802fd728-3bed-4f31-9931-d95983d6d45b	5acab47a-ebce-406b-aaea-a826b37a7a67	t	${role_manage-consent}	manage-consent	5928e5d4-c400-4150-9107-da98acace8cf	5acab47a-ebce-406b-aaea-a826b37a7a67	\N
4d9472be-ba3b-475c-a64a-5b49404bf4ff	5acab47a-ebce-406b-aaea-a826b37a7a67	t	${role_view-groups}	view-groups	5928e5d4-c400-4150-9107-da98acace8cf	5acab47a-ebce-406b-aaea-a826b37a7a67	\N
9dc9e5d8-22bd-4bd0-90e8-b1f0c66f0a33	5acab47a-ebce-406b-aaea-a826b37a7a67	t	${role_delete-account}	delete-account	5928e5d4-c400-4150-9107-da98acace8cf	5acab47a-ebce-406b-aaea-a826b37a7a67	\N
1797b55b-bcfd-4c8e-baa2-2eba6861b47f	db6561a3-eade-43c8-aff5-28c54ee54e19	t	${role_impersonation}	impersonation	331e6113-4db4-4433-997e-09db1350e12a	db6561a3-eade-43c8-aff5-28c54ee54e19	\N
02b78066-9bae-42c8-b4c1-e786fe9ca4c2	8b21bcbe-534e-4196-a20e-4f2592399d8c	t	${role_impersonation}	impersonation	5928e5d4-c400-4150-9107-da98acace8cf	8b21bcbe-534e-4196-a20e-4f2592399d8c	\N
cb7ad2be-abc9-4446-b90c-7e84ac31c125	eea055c7-237a-45c7-aa48-0f8c0c89f9ba	t	${role_read-token}	read-token	5928e5d4-c400-4150-9107-da98acace8cf	eea055c7-237a-45c7-aa48-0f8c0c89f9ba	\N
c7fd25b0-998c-479f-9277-86d868a80406	5928e5d4-c400-4150-9107-da98acace8cf	f	${role_offline-access}	offline_access	5928e5d4-c400-4150-9107-da98acace8cf	\N	\N
e8bc09aa-0214-4146-a484-b2d1021a0cac	5928e5d4-c400-4150-9107-da98acace8cf	f	${role_uma_authorization}	uma_authorization	5928e5d4-c400-4150-9107-da98acace8cf	\N	\N
1c7b5d9f-36d2-4558-b0e3-d68d664107ce	5928e5d4-c400-4150-9107-da98acace8cf	f	Super Administrator	SUPER_ADMIN	5928e5d4-c400-4150-9107-da98acace8cf	\N	\N
4bd98669-ef63-48e8-b3b4-de640fc21203	5928e5d4-c400-4150-9107-da98acace8cf	f	Administrator	ADMIN	5928e5d4-c400-4150-9107-da98acace8cf	\N	\N
fb12c79b-872e-4c73-b7b8-69624b44be5d	5928e5d4-c400-4150-9107-da98acace8cf	f	Finance User	FINANCE	5928e5d4-c400-4150-9107-da98acace8cf	\N	\N
16f52ba3-9bf0-43dc-b954-19febf7fd656	5928e5d4-c400-4150-9107-da98acace8cf	f	Human Resource User	HR	5928e5d4-c400-4150-9107-da98acace8cf	\N	\N
1c0ebed7-b968-41ba-a163-38f5574e3ce9	5928e5d4-c400-4150-9107-da98acace8cf	f	Regular User	USER	5928e5d4-c400-4150-9107-da98acace8cf	\N	\N
\.


--
-- Data for Name: login_failure; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.login_failure (realm_id, user_id, failed_login_not_before, num_failures, num_temporary_lockouts, last_failure, last_ip_failure, num_secondary_auth_failures) FROM stdin;
\.


--
-- Data for Name: migration_model; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.migration_model (id, version, update_time) FROM stdin;
o5zyb	26.7.4	1792569169
\.


--
-- Data for Name: offline_client_session; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.offline_client_session (user_session_id, client_id, offline_flag, "timestamp", data, client_storage_provider, external_client_id, version, realm_id) FROM stdin;
\.


--
-- Data for Name: offline_user_session; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.offline_user_session (user_session_id, user_id, realm_id, created_on, offline_flag, data, last_session_refresh, broker_session_id, version, remember_me) FROM stdin;
\.


--
-- Data for Name: org; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.org (id, enabled, realm_id, group_id, name, description, alias, redirect_url) FROM stdin;
\.


--
-- Data for Name: org_domain; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.org_domain (id, name, verified, org_id) FROM stdin;
\.


--
-- Data for Name: org_invitation; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.org_invitation (id, organization_id, email, first_name, last_name, created_at, expires_at, invite_link) FROM stdin;
\.


--
-- Data for Name: outbox_entry; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.outbox_entry (id, entry_kind, realm_id, owner_id, container_id, correlation_id, entry_type, payload, metadata, status, attempts, next_attempt_at, last_error, created_at, delivered_at) FROM stdin;
\.


--
-- Data for Name: policy_config; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.policy_config (policy_id, name, value) FROM stdin;
\.


--
-- Data for Name: protocol_mapper; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.protocol_mapper (id, name, protocol, protocol_mapper_name, client_id, client_scope_id) FROM stdin;
dbb40e45-3d1a-489c-9987-3559514cde1e	audience resolve	openid-connect	oidc-audience-resolve-mapper	00b14034-0863-4908-85f7-81849f8af952	\N
4f384811-f6e8-4176-a5c3-fbf48c140ad0	locale	openid-connect	oidc-usermodel-attribute-mapper	a7ac4e8e-3117-44a8-95b0-f02c71ded253	\N
d6059818-32d5-4288-a24e-55d6d1830e10	role list	saml	saml-role-list-mapper	\N	e405615b-e22c-44eb-80ae-84dff928cd7f
ed310dfd-f647-4e0a-b1e4-63c095a48e73	organization	saml	saml-organization-membership-mapper	\N	be4015dd-3b59-4cfa-a3e4-9c0112a90d5d
0ff8aa27-091d-454d-9c4e-6ba1139ca721	AuthnContextClassRef	saml	saml-authn-context-class-ref-mapper	\N	549bfb16-8cc0-4634-ae5b-f4073270b3e4
6050d32a-e7df-49d3-89ef-e06d8e959aaa	full name	openid-connect	oidc-full-name-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
40dc094d-ebf3-42af-8c8c-8ec80678e7eb	family name	openid-connect	oidc-usermodel-attribute-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
d023a156-886a-4d3b-88dd-70584dafb135	given name	openid-connect	oidc-usermodel-attribute-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
8107cb7a-2140-4dfc-8e88-90b5b1605b99	middle name	openid-connect	oidc-usermodel-attribute-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
0fd3b82d-43bf-4399-9538-37ebfc5e522d	nickname	openid-connect	oidc-usermodel-attribute-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
0920c905-73d8-45e2-86dc-61c257ed5d8a	username	openid-connect	oidc-usermodel-attribute-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
f8a8a7cc-9fca-4cf7-859b-16d07cefe228	profile	openid-connect	oidc-usermodel-attribute-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
9ea1f15c-b7a5-4fce-94ca-0d6a76793fc1	picture	openid-connect	oidc-usermodel-attribute-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
a1003b07-384b-4465-b6e9-c22bf2b3fe98	website	openid-connect	oidc-usermodel-attribute-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
d5c122c7-362a-412d-8122-c015ed4494f8	gender	openid-connect	oidc-usermodel-attribute-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
7b1f2aab-f496-4181-9184-3e15e448edf5	birthdate	openid-connect	oidc-usermodel-attribute-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
9120e086-35d3-4906-9ceb-f164caa195c5	zoneinfo	openid-connect	oidc-usermodel-attribute-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
9b7a8171-a6ce-4af3-a937-f3f9735c5b95	locale	openid-connect	oidc-usermodel-attribute-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
4887fa13-8419-400a-860f-cc2f5367333a	updated at	openid-connect	oidc-usermodel-attribute-mapper	\N	b448fe6b-e8e6-4adc-9ff7-45628fcb4560
460c4000-6ec8-410e-aeb8-1c17369402d4	email	openid-connect	oidc-usermodel-attribute-mapper	\N	f09699e1-d95e-4dae-8187-1b6380b82a40
ac18595c-ce0e-40a5-b892-336aff88c518	email verified	openid-connect	oidc-usermodel-property-mapper	\N	f09699e1-d95e-4dae-8187-1b6380b82a40
e7cba4a0-38f8-4a56-9b38-a1f735072cdd	address	openid-connect	oidc-address-mapper	\N	ee3ade41-39d1-441d-9922-f7dc73cd8f24
5a234956-2522-48a1-9f86-b58d6973721b	phone number	openid-connect	oidc-usermodel-attribute-mapper	\N	2f0d6ac3-76de-4d40-9825-5db7a96054a2
05d42df9-ad3d-4d2c-85ce-01c60ead3c9b	phone number verified	openid-connect	oidc-usermodel-attribute-mapper	\N	2f0d6ac3-76de-4d40-9825-5db7a96054a2
24866c9b-e0cc-4fc9-947b-e9c7867652a7	realm roles	openid-connect	oidc-usermodel-realm-role-mapper	\N	335a2bcc-3f75-4032-bd25-d368c817655d
37ab06f1-33a9-40d8-b0e4-5fb3e3c0775a	client roles	openid-connect	oidc-usermodel-client-role-mapper	\N	335a2bcc-3f75-4032-bd25-d368c817655d
fcf59a06-060d-4741-86bb-2cb43d58011e	audience resolve	openid-connect	oidc-audience-resolve-mapper	\N	335a2bcc-3f75-4032-bd25-d368c817655d
b44a9554-d27c-41d7-aba7-5d12393a2e7b	allowed web origins	openid-connect	oidc-allowed-origins-mapper	\N	31bb7ee4-e3fa-4a1b-a242-eb86a98ea2c8
50b7964b-a3a0-427a-b5d6-a424428c3824	upn	openid-connect	oidc-usermodel-attribute-mapper	\N	6977c07d-a0b9-4661-9ab0-8b5dcc5df3ae
c3a62b74-cc04-4853-b161-e6714b0b5d27	groups	openid-connect	oidc-usermodel-realm-role-mapper	\N	6977c07d-a0b9-4661-9ab0-8b5dcc5df3ae
305e7415-1621-4d2f-a5b5-147a675e9ffa	acr loa level	openid-connect	oidc-acr-mapper	\N	ec99790c-0896-4e6b-962a-a4295e6ce499
46d26ae1-dcf9-4670-80dd-6f57ca351852	auth_time	openid-connect	oidc-usersessionmodel-note-mapper	\N	468ad7f4-9f9f-4b4b-be02-4305be58e7dd
c3677790-5163-4911-8051-942efc183ad5	sub	openid-connect	oidc-sub-mapper	\N	468ad7f4-9f9f-4b4b-be02-4305be58e7dd
f11aad6d-662d-4fe9-ac8d-098f74616d64	Client ID	openid-connect	oidc-usersessionmodel-note-mapper	\N	ec60fad4-9c97-450b-bb63-73bfdd9a8b0f
4734c2d1-8108-4060-8cf2-bcf291495b6f	Client Host	openid-connect	oidc-usersessionmodel-note-mapper	\N	ec60fad4-9c97-450b-bb63-73bfdd9a8b0f
6dc3d307-f9c2-45bf-9846-6aec2feb5318	Client IP Address	openid-connect	oidc-usersessionmodel-note-mapper	\N	ec60fad4-9c97-450b-bb63-73bfdd9a8b0f
956ce445-d165-4445-8f41-18e460a3ac24	organization	openid-connect	oidc-organization-membership-mapper	\N	bb5bb9a1-ba1e-432a-a857-c6c0291b2c54
0e1b2471-3dd6-4c5e-be86-957d1ea453a4	audience resolve	openid-connect	oidc-audience-resolve-mapper	f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	\N
ae2eae5c-fc1f-4f3a-a104-199b724b8695	role list	saml	saml-role-list-mapper	\N	e134ec31-7d01-464d-b16b-4a71984873a1
8b64ebc0-906a-434f-8acc-ca625e83a0ef	organization	saml	saml-organization-membership-mapper	\N	5dab62a2-1f8c-4803-8c32-44158a24ab0a
c3bef963-cafd-4cb5-953b-909e2929d34b	AuthnContextClassRef	saml	saml-authn-context-class-ref-mapper	\N	e8a13582-4580-44e2-ab5c-f8b0a8ce4b52
0919f8db-ef86-4047-85ca-c7567d0e6d49	full name	openid-connect	oidc-full-name-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
54f768e0-23c7-4431-8ce8-a1f2aa078e46	family name	openid-connect	oidc-usermodel-attribute-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
10f95fdd-6c91-4ab6-b8fd-660367747276	given name	openid-connect	oidc-usermodel-attribute-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
6a104d9a-914f-4018-a262-98b5153def14	middle name	openid-connect	oidc-usermodel-attribute-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
38757b01-f31c-48c4-aa0d-820e25f31c69	nickname	openid-connect	oidc-usermodel-attribute-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
94ab3372-f8e5-431e-a6ae-1d65601ea110	username	openid-connect	oidc-usermodel-attribute-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
73645be4-6eef-4442-8c73-37a159e86faf	profile	openid-connect	oidc-usermodel-attribute-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
1e12414d-36eb-4c40-ad7e-279c681a0f6a	picture	openid-connect	oidc-usermodel-attribute-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
d5cf4377-a54b-43db-97b9-cd2ebff0eed4	website	openid-connect	oidc-usermodel-attribute-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
c77770d0-02fa-477f-965e-dcafc2f7637c	gender	openid-connect	oidc-usermodel-attribute-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
5736e663-c714-482c-8b84-937c6ec3e8c3	birthdate	openid-connect	oidc-usermodel-attribute-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
7b4888a3-e8ed-4297-89df-474d097c802f	zoneinfo	openid-connect	oidc-usermodel-attribute-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
5f5c944c-f89c-47d3-a07a-27b5eff31c5a	locale	openid-connect	oidc-usermodel-attribute-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
d78c2ebf-3d1b-4e11-91cb-7888a39addaa	updated at	openid-connect	oidc-usermodel-attribute-mapper	\N	ffb9f715-58c7-4afe-89ed-98862944e1f5
b6abdf34-737f-454b-847b-e95e39137dde	email	openid-connect	oidc-usermodel-attribute-mapper	\N	e8ef943d-eef2-4d47-9710-d7105d4a9e80
1b330d9c-40c1-4bd7-b6cf-fcb638c3302d	email verified	openid-connect	oidc-usermodel-property-mapper	\N	e8ef943d-eef2-4d47-9710-d7105d4a9e80
f6e03e8f-39fb-46be-9d06-c8d9cb31efdd	address	openid-connect	oidc-address-mapper	\N	32c939de-30ec-4a62-96c0-00847c91aacf
ba44cc8c-b378-4187-b686-be259bfbf93b	phone number	openid-connect	oidc-usermodel-attribute-mapper	\N	6b2b117d-a23d-4844-9cbe-821f02964cf7
5f74333e-655b-47b1-a7c6-20e3a80a6fb0	phone number verified	openid-connect	oidc-usermodel-attribute-mapper	\N	6b2b117d-a23d-4844-9cbe-821f02964cf7
aa3bfd31-74e1-4793-a99e-96fe8270da48	realm roles	openid-connect	oidc-usermodel-realm-role-mapper	\N	5ebfdbc1-e201-418c-b5af-8e28d36bf4f8
f0fcf6f3-62a1-4fec-b516-b57ef55a767f	client roles	openid-connect	oidc-usermodel-client-role-mapper	\N	5ebfdbc1-e201-418c-b5af-8e28d36bf4f8
b8a50523-0db8-40cb-9562-013b231bd328	audience resolve	openid-connect	oidc-audience-resolve-mapper	\N	5ebfdbc1-e201-418c-b5af-8e28d36bf4f8
859b1f19-ef22-4249-8e0c-11265e2cedd5	allowed web origins	openid-connect	oidc-allowed-origins-mapper	\N	e9472182-f327-442e-9c0b-4c7745ea2ae8
dd1ebf5c-32fd-4f25-a0ea-c0e0cf834e8f	upn	openid-connect	oidc-usermodel-attribute-mapper	\N	bd194148-647b-4081-bb24-5c760c78d0e2
9d41e23e-13d2-4f42-932b-facf6476bee6	groups	openid-connect	oidc-usermodel-realm-role-mapper	\N	bd194148-647b-4081-bb24-5c760c78d0e2
68450db1-e90e-48f7-b305-4a903fe14fb0	acr loa level	openid-connect	oidc-acr-mapper	\N	53e24107-4a5b-4e1b-9c18-478e75199b39
179d95b9-2f6b-477c-8854-df7b4089ff2b	auth_time	openid-connect	oidc-usersessionmodel-note-mapper	\N	c0da43db-fc02-412e-829f-3d06eb946b76
2c6c9f3d-a2b0-4fac-8993-a31ef24eec3a	sub	openid-connect	oidc-sub-mapper	\N	c0da43db-fc02-412e-829f-3d06eb946b76
e5cc6be4-63f6-4d5a-877c-e1ea2b6820c0	Client ID	openid-connect	oidc-usersessionmodel-note-mapper	\N	045fcd1d-8a27-47c2-812d-5e4b2cc0b483
8a69d488-c871-48ca-be7e-2e1ada191097	Client Host	openid-connect	oidc-usersessionmodel-note-mapper	\N	045fcd1d-8a27-47c2-812d-5e4b2cc0b483
cd67005b-0b76-4381-86f4-d394029e3b52	Client IP Address	openid-connect	oidc-usersessionmodel-note-mapper	\N	045fcd1d-8a27-47c2-812d-5e4b2cc0b483
d4214af9-e0b8-45ca-943e-bd61bc8a95ca	organization	openid-connect	oidc-organization-membership-mapper	\N	cc70a7eb-bb51-4244-966d-e495cfe0f2bd
3c29b84f-7dd3-4705-894c-1f967dd925c2	locale	openid-connect	oidc-usermodel-attribute-mapper	02921f33-7315-4da6-aa49-bb63211e78df	\N
\.


--
-- Data for Name: protocol_mapper_config; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.protocol_mapper_config (protocol_mapper_id, value, name) FROM stdin;
4f384811-f6e8-4176-a5c3-fbf48c140ad0	true	introspection.token.claim
4f384811-f6e8-4176-a5c3-fbf48c140ad0	true	userinfo.token.claim
4f384811-f6e8-4176-a5c3-fbf48c140ad0	locale	user.attribute
4f384811-f6e8-4176-a5c3-fbf48c140ad0	true	id.token.claim
4f384811-f6e8-4176-a5c3-fbf48c140ad0	true	access.token.claim
4f384811-f6e8-4176-a5c3-fbf48c140ad0	locale	claim.name
4f384811-f6e8-4176-a5c3-fbf48c140ad0	String	jsonType.label
d6059818-32d5-4288-a24e-55d6d1830e10	false	single
d6059818-32d5-4288-a24e-55d6d1830e10	Basic	attribute.nameformat
d6059818-32d5-4288-a24e-55d6d1830e10	Role	attribute.name
0920c905-73d8-45e2-86dc-61c257ed5d8a	true	introspection.token.claim
0920c905-73d8-45e2-86dc-61c257ed5d8a	true	userinfo.token.claim
0920c905-73d8-45e2-86dc-61c257ed5d8a	username	user.attribute
0920c905-73d8-45e2-86dc-61c257ed5d8a	true	id.token.claim
0920c905-73d8-45e2-86dc-61c257ed5d8a	true	access.token.claim
0920c905-73d8-45e2-86dc-61c257ed5d8a	preferred_username	claim.name
0920c905-73d8-45e2-86dc-61c257ed5d8a	String	jsonType.label
0fd3b82d-43bf-4399-9538-37ebfc5e522d	true	introspection.token.claim
0fd3b82d-43bf-4399-9538-37ebfc5e522d	true	userinfo.token.claim
0fd3b82d-43bf-4399-9538-37ebfc5e522d	nickname	user.attribute
0fd3b82d-43bf-4399-9538-37ebfc5e522d	true	id.token.claim
0fd3b82d-43bf-4399-9538-37ebfc5e522d	true	access.token.claim
0fd3b82d-43bf-4399-9538-37ebfc5e522d	nickname	claim.name
0fd3b82d-43bf-4399-9538-37ebfc5e522d	String	jsonType.label
40dc094d-ebf3-42af-8c8c-8ec80678e7eb	true	introspection.token.claim
40dc094d-ebf3-42af-8c8c-8ec80678e7eb	true	userinfo.token.claim
40dc094d-ebf3-42af-8c8c-8ec80678e7eb	lastName	user.attribute
40dc094d-ebf3-42af-8c8c-8ec80678e7eb	true	id.token.claim
40dc094d-ebf3-42af-8c8c-8ec80678e7eb	true	access.token.claim
40dc094d-ebf3-42af-8c8c-8ec80678e7eb	family_name	claim.name
40dc094d-ebf3-42af-8c8c-8ec80678e7eb	String	jsonType.label
4887fa13-8419-400a-860f-cc2f5367333a	true	introspection.token.claim
4887fa13-8419-400a-860f-cc2f5367333a	true	userinfo.token.claim
4887fa13-8419-400a-860f-cc2f5367333a	updatedAt	user.attribute
4887fa13-8419-400a-860f-cc2f5367333a	true	id.token.claim
4887fa13-8419-400a-860f-cc2f5367333a	true	access.token.claim
4887fa13-8419-400a-860f-cc2f5367333a	updated_at	claim.name
4887fa13-8419-400a-860f-cc2f5367333a	long	jsonType.label
6050d32a-e7df-49d3-89ef-e06d8e959aaa	true	introspection.token.claim
6050d32a-e7df-49d3-89ef-e06d8e959aaa	true	userinfo.token.claim
6050d32a-e7df-49d3-89ef-e06d8e959aaa	true	id.token.claim
6050d32a-e7df-49d3-89ef-e06d8e959aaa	true	access.token.claim
7b1f2aab-f496-4181-9184-3e15e448edf5	true	introspection.token.claim
7b1f2aab-f496-4181-9184-3e15e448edf5	true	userinfo.token.claim
7b1f2aab-f496-4181-9184-3e15e448edf5	birthdate	user.attribute
7b1f2aab-f496-4181-9184-3e15e448edf5	true	id.token.claim
7b1f2aab-f496-4181-9184-3e15e448edf5	true	access.token.claim
7b1f2aab-f496-4181-9184-3e15e448edf5	birthdate	claim.name
7b1f2aab-f496-4181-9184-3e15e448edf5	String	jsonType.label
8107cb7a-2140-4dfc-8e88-90b5b1605b99	true	introspection.token.claim
8107cb7a-2140-4dfc-8e88-90b5b1605b99	true	userinfo.token.claim
8107cb7a-2140-4dfc-8e88-90b5b1605b99	middleName	user.attribute
8107cb7a-2140-4dfc-8e88-90b5b1605b99	true	id.token.claim
8107cb7a-2140-4dfc-8e88-90b5b1605b99	true	access.token.claim
8107cb7a-2140-4dfc-8e88-90b5b1605b99	middle_name	claim.name
8107cb7a-2140-4dfc-8e88-90b5b1605b99	String	jsonType.label
9120e086-35d3-4906-9ceb-f164caa195c5	true	introspection.token.claim
9120e086-35d3-4906-9ceb-f164caa195c5	true	userinfo.token.claim
9120e086-35d3-4906-9ceb-f164caa195c5	zoneinfo	user.attribute
9120e086-35d3-4906-9ceb-f164caa195c5	true	id.token.claim
9120e086-35d3-4906-9ceb-f164caa195c5	true	access.token.claim
9120e086-35d3-4906-9ceb-f164caa195c5	zoneinfo	claim.name
9120e086-35d3-4906-9ceb-f164caa195c5	String	jsonType.label
9b7a8171-a6ce-4af3-a937-f3f9735c5b95	true	introspection.token.claim
9b7a8171-a6ce-4af3-a937-f3f9735c5b95	true	userinfo.token.claim
9b7a8171-a6ce-4af3-a937-f3f9735c5b95	locale	user.attribute
9b7a8171-a6ce-4af3-a937-f3f9735c5b95	true	id.token.claim
9b7a8171-a6ce-4af3-a937-f3f9735c5b95	true	access.token.claim
9b7a8171-a6ce-4af3-a937-f3f9735c5b95	locale	claim.name
9b7a8171-a6ce-4af3-a937-f3f9735c5b95	String	jsonType.label
9ea1f15c-b7a5-4fce-94ca-0d6a76793fc1	true	introspection.token.claim
9ea1f15c-b7a5-4fce-94ca-0d6a76793fc1	true	userinfo.token.claim
9ea1f15c-b7a5-4fce-94ca-0d6a76793fc1	picture	user.attribute
9ea1f15c-b7a5-4fce-94ca-0d6a76793fc1	true	id.token.claim
9ea1f15c-b7a5-4fce-94ca-0d6a76793fc1	true	access.token.claim
9ea1f15c-b7a5-4fce-94ca-0d6a76793fc1	picture	claim.name
9ea1f15c-b7a5-4fce-94ca-0d6a76793fc1	String	jsonType.label
a1003b07-384b-4465-b6e9-c22bf2b3fe98	true	introspection.token.claim
a1003b07-384b-4465-b6e9-c22bf2b3fe98	true	userinfo.token.claim
a1003b07-384b-4465-b6e9-c22bf2b3fe98	website	user.attribute
a1003b07-384b-4465-b6e9-c22bf2b3fe98	true	id.token.claim
a1003b07-384b-4465-b6e9-c22bf2b3fe98	true	access.token.claim
a1003b07-384b-4465-b6e9-c22bf2b3fe98	website	claim.name
a1003b07-384b-4465-b6e9-c22bf2b3fe98	String	jsonType.label
d023a156-886a-4d3b-88dd-70584dafb135	true	introspection.token.claim
d023a156-886a-4d3b-88dd-70584dafb135	true	userinfo.token.claim
d023a156-886a-4d3b-88dd-70584dafb135	firstName	user.attribute
d023a156-886a-4d3b-88dd-70584dafb135	true	id.token.claim
d023a156-886a-4d3b-88dd-70584dafb135	true	access.token.claim
d023a156-886a-4d3b-88dd-70584dafb135	given_name	claim.name
d023a156-886a-4d3b-88dd-70584dafb135	String	jsonType.label
d5c122c7-362a-412d-8122-c015ed4494f8	true	introspection.token.claim
d5c122c7-362a-412d-8122-c015ed4494f8	true	userinfo.token.claim
d5c122c7-362a-412d-8122-c015ed4494f8	gender	user.attribute
d5c122c7-362a-412d-8122-c015ed4494f8	true	id.token.claim
d5c122c7-362a-412d-8122-c015ed4494f8	true	access.token.claim
d5c122c7-362a-412d-8122-c015ed4494f8	gender	claim.name
d5c122c7-362a-412d-8122-c015ed4494f8	String	jsonType.label
f8a8a7cc-9fca-4cf7-859b-16d07cefe228	true	introspection.token.claim
f8a8a7cc-9fca-4cf7-859b-16d07cefe228	true	userinfo.token.claim
f8a8a7cc-9fca-4cf7-859b-16d07cefe228	profile	user.attribute
f8a8a7cc-9fca-4cf7-859b-16d07cefe228	true	id.token.claim
f8a8a7cc-9fca-4cf7-859b-16d07cefe228	true	access.token.claim
f8a8a7cc-9fca-4cf7-859b-16d07cefe228	profile	claim.name
f8a8a7cc-9fca-4cf7-859b-16d07cefe228	String	jsonType.label
460c4000-6ec8-410e-aeb8-1c17369402d4	true	introspection.token.claim
460c4000-6ec8-410e-aeb8-1c17369402d4	true	userinfo.token.claim
460c4000-6ec8-410e-aeb8-1c17369402d4	email	user.attribute
460c4000-6ec8-410e-aeb8-1c17369402d4	true	id.token.claim
460c4000-6ec8-410e-aeb8-1c17369402d4	true	access.token.claim
460c4000-6ec8-410e-aeb8-1c17369402d4	email	claim.name
460c4000-6ec8-410e-aeb8-1c17369402d4	String	jsonType.label
ac18595c-ce0e-40a5-b892-336aff88c518	true	introspection.token.claim
ac18595c-ce0e-40a5-b892-336aff88c518	true	userinfo.token.claim
ac18595c-ce0e-40a5-b892-336aff88c518	emailVerified	user.attribute
ac18595c-ce0e-40a5-b892-336aff88c518	true	id.token.claim
ac18595c-ce0e-40a5-b892-336aff88c518	true	access.token.claim
ac18595c-ce0e-40a5-b892-336aff88c518	email_verified	claim.name
ac18595c-ce0e-40a5-b892-336aff88c518	boolean	jsonType.label
e7cba4a0-38f8-4a56-9b38-a1f735072cdd	formatted	user.attribute.formatted
e7cba4a0-38f8-4a56-9b38-a1f735072cdd	country	user.attribute.country
e7cba4a0-38f8-4a56-9b38-a1f735072cdd	true	introspection.token.claim
e7cba4a0-38f8-4a56-9b38-a1f735072cdd	postal_code	user.attribute.postal_code
e7cba4a0-38f8-4a56-9b38-a1f735072cdd	true	userinfo.token.claim
e7cba4a0-38f8-4a56-9b38-a1f735072cdd	street	user.attribute.street
e7cba4a0-38f8-4a56-9b38-a1f735072cdd	true	id.token.claim
e7cba4a0-38f8-4a56-9b38-a1f735072cdd	region	user.attribute.region
e7cba4a0-38f8-4a56-9b38-a1f735072cdd	true	access.token.claim
e7cba4a0-38f8-4a56-9b38-a1f735072cdd	locality	user.attribute.locality
05d42df9-ad3d-4d2c-85ce-01c60ead3c9b	true	introspection.token.claim
05d42df9-ad3d-4d2c-85ce-01c60ead3c9b	true	userinfo.token.claim
05d42df9-ad3d-4d2c-85ce-01c60ead3c9b	phoneNumberVerified	user.attribute
05d42df9-ad3d-4d2c-85ce-01c60ead3c9b	true	id.token.claim
05d42df9-ad3d-4d2c-85ce-01c60ead3c9b	true	access.token.claim
05d42df9-ad3d-4d2c-85ce-01c60ead3c9b	phone_number_verified	claim.name
05d42df9-ad3d-4d2c-85ce-01c60ead3c9b	boolean	jsonType.label
5a234956-2522-48a1-9f86-b58d6973721b	true	introspection.token.claim
5a234956-2522-48a1-9f86-b58d6973721b	true	userinfo.token.claim
5a234956-2522-48a1-9f86-b58d6973721b	phoneNumber	user.attribute
5a234956-2522-48a1-9f86-b58d6973721b	true	id.token.claim
5a234956-2522-48a1-9f86-b58d6973721b	true	access.token.claim
5a234956-2522-48a1-9f86-b58d6973721b	phone_number	claim.name
5a234956-2522-48a1-9f86-b58d6973721b	String	jsonType.label
24866c9b-e0cc-4fc9-947b-e9c7867652a7	true	introspection.token.claim
24866c9b-e0cc-4fc9-947b-e9c7867652a7	true	multivalued
24866c9b-e0cc-4fc9-947b-e9c7867652a7	foo	user.attribute
24866c9b-e0cc-4fc9-947b-e9c7867652a7	true	access.token.claim
24866c9b-e0cc-4fc9-947b-e9c7867652a7	realm_access.roles	claim.name
24866c9b-e0cc-4fc9-947b-e9c7867652a7	String	jsonType.label
37ab06f1-33a9-40d8-b0e4-5fb3e3c0775a	true	introspection.token.claim
37ab06f1-33a9-40d8-b0e4-5fb3e3c0775a	true	multivalued
37ab06f1-33a9-40d8-b0e4-5fb3e3c0775a	foo	user.attribute
37ab06f1-33a9-40d8-b0e4-5fb3e3c0775a	true	access.token.claim
37ab06f1-33a9-40d8-b0e4-5fb3e3c0775a	resource_access.${client_id}.roles	claim.name
37ab06f1-33a9-40d8-b0e4-5fb3e3c0775a	String	jsonType.label
fcf59a06-060d-4741-86bb-2cb43d58011e	true	introspection.token.claim
fcf59a06-060d-4741-86bb-2cb43d58011e	true	access.token.claim
b44a9554-d27c-41d7-aba7-5d12393a2e7b	true	introspection.token.claim
b44a9554-d27c-41d7-aba7-5d12393a2e7b	true	access.token.claim
50b7964b-a3a0-427a-b5d6-a424428c3824	true	introspection.token.claim
50b7964b-a3a0-427a-b5d6-a424428c3824	true	userinfo.token.claim
50b7964b-a3a0-427a-b5d6-a424428c3824	username	user.attribute
50b7964b-a3a0-427a-b5d6-a424428c3824	true	id.token.claim
50b7964b-a3a0-427a-b5d6-a424428c3824	true	access.token.claim
50b7964b-a3a0-427a-b5d6-a424428c3824	upn	claim.name
50b7964b-a3a0-427a-b5d6-a424428c3824	String	jsonType.label
c3a62b74-cc04-4853-b161-e6714b0b5d27	true	introspection.token.claim
c3a62b74-cc04-4853-b161-e6714b0b5d27	true	multivalued
c3a62b74-cc04-4853-b161-e6714b0b5d27	foo	user.attribute
c3a62b74-cc04-4853-b161-e6714b0b5d27	true	id.token.claim
c3a62b74-cc04-4853-b161-e6714b0b5d27	true	access.token.claim
c3a62b74-cc04-4853-b161-e6714b0b5d27	groups	claim.name
c3a62b74-cc04-4853-b161-e6714b0b5d27	String	jsonType.label
305e7415-1621-4d2f-a5b5-147a675e9ffa	true	introspection.token.claim
305e7415-1621-4d2f-a5b5-147a675e9ffa	true	id.token.claim
305e7415-1621-4d2f-a5b5-147a675e9ffa	true	access.token.claim
46d26ae1-dcf9-4670-80dd-6f57ca351852	AUTH_TIME	user.session.note
46d26ae1-dcf9-4670-80dd-6f57ca351852	true	introspection.token.claim
46d26ae1-dcf9-4670-80dd-6f57ca351852	true	id.token.claim
46d26ae1-dcf9-4670-80dd-6f57ca351852	true	access.token.claim
46d26ae1-dcf9-4670-80dd-6f57ca351852	auth_time	claim.name
46d26ae1-dcf9-4670-80dd-6f57ca351852	long	jsonType.label
c3677790-5163-4911-8051-942efc183ad5	true	introspection.token.claim
c3677790-5163-4911-8051-942efc183ad5	true	access.token.claim
4734c2d1-8108-4060-8cf2-bcf291495b6f	clientHost	user.session.note
4734c2d1-8108-4060-8cf2-bcf291495b6f	true	introspection.token.claim
4734c2d1-8108-4060-8cf2-bcf291495b6f	true	id.token.claim
4734c2d1-8108-4060-8cf2-bcf291495b6f	true	access.token.claim
4734c2d1-8108-4060-8cf2-bcf291495b6f	clientHost	claim.name
4734c2d1-8108-4060-8cf2-bcf291495b6f	String	jsonType.label
6dc3d307-f9c2-45bf-9846-6aec2feb5318	clientAddress	user.session.note
6dc3d307-f9c2-45bf-9846-6aec2feb5318	true	introspection.token.claim
6dc3d307-f9c2-45bf-9846-6aec2feb5318	true	id.token.claim
6dc3d307-f9c2-45bf-9846-6aec2feb5318	true	access.token.claim
6dc3d307-f9c2-45bf-9846-6aec2feb5318	clientAddress	claim.name
6dc3d307-f9c2-45bf-9846-6aec2feb5318	String	jsonType.label
f11aad6d-662d-4fe9-ac8d-098f74616d64	client_id	user.session.note
f11aad6d-662d-4fe9-ac8d-098f74616d64	true	introspection.token.claim
f11aad6d-662d-4fe9-ac8d-098f74616d64	true	id.token.claim
f11aad6d-662d-4fe9-ac8d-098f74616d64	true	access.token.claim
f11aad6d-662d-4fe9-ac8d-098f74616d64	client_id	claim.name
f11aad6d-662d-4fe9-ac8d-098f74616d64	String	jsonType.label
956ce445-d165-4445-8f41-18e460a3ac24	true	introspection.token.claim
956ce445-d165-4445-8f41-18e460a3ac24	true	multivalued
956ce445-d165-4445-8f41-18e460a3ac24	true	id.token.claim
956ce445-d165-4445-8f41-18e460a3ac24	true	access.token.claim
956ce445-d165-4445-8f41-18e460a3ac24	organization	claim.name
956ce445-d165-4445-8f41-18e460a3ac24	String	jsonType.label
ae2eae5c-fc1f-4f3a-a104-199b724b8695	false	single
ae2eae5c-fc1f-4f3a-a104-199b724b8695	Basic	attribute.nameformat
ae2eae5c-fc1f-4f3a-a104-199b724b8695	Role	attribute.name
0919f8db-ef86-4047-85ca-c7567d0e6d49	true	introspection.token.claim
0919f8db-ef86-4047-85ca-c7567d0e6d49	true	userinfo.token.claim
0919f8db-ef86-4047-85ca-c7567d0e6d49	true	id.token.claim
0919f8db-ef86-4047-85ca-c7567d0e6d49	true	access.token.claim
10f95fdd-6c91-4ab6-b8fd-660367747276	true	introspection.token.claim
10f95fdd-6c91-4ab6-b8fd-660367747276	true	userinfo.token.claim
10f95fdd-6c91-4ab6-b8fd-660367747276	firstName	user.attribute
10f95fdd-6c91-4ab6-b8fd-660367747276	true	id.token.claim
10f95fdd-6c91-4ab6-b8fd-660367747276	true	access.token.claim
10f95fdd-6c91-4ab6-b8fd-660367747276	given_name	claim.name
10f95fdd-6c91-4ab6-b8fd-660367747276	String	jsonType.label
1e12414d-36eb-4c40-ad7e-279c681a0f6a	true	introspection.token.claim
1e12414d-36eb-4c40-ad7e-279c681a0f6a	true	userinfo.token.claim
1e12414d-36eb-4c40-ad7e-279c681a0f6a	picture	user.attribute
1e12414d-36eb-4c40-ad7e-279c681a0f6a	true	id.token.claim
1e12414d-36eb-4c40-ad7e-279c681a0f6a	true	access.token.claim
1e12414d-36eb-4c40-ad7e-279c681a0f6a	picture	claim.name
1e12414d-36eb-4c40-ad7e-279c681a0f6a	String	jsonType.label
38757b01-f31c-48c4-aa0d-820e25f31c69	true	introspection.token.claim
38757b01-f31c-48c4-aa0d-820e25f31c69	true	userinfo.token.claim
38757b01-f31c-48c4-aa0d-820e25f31c69	nickname	user.attribute
38757b01-f31c-48c4-aa0d-820e25f31c69	true	id.token.claim
38757b01-f31c-48c4-aa0d-820e25f31c69	true	access.token.claim
38757b01-f31c-48c4-aa0d-820e25f31c69	nickname	claim.name
38757b01-f31c-48c4-aa0d-820e25f31c69	String	jsonType.label
54f768e0-23c7-4431-8ce8-a1f2aa078e46	true	introspection.token.claim
54f768e0-23c7-4431-8ce8-a1f2aa078e46	true	userinfo.token.claim
54f768e0-23c7-4431-8ce8-a1f2aa078e46	lastName	user.attribute
54f768e0-23c7-4431-8ce8-a1f2aa078e46	true	id.token.claim
54f768e0-23c7-4431-8ce8-a1f2aa078e46	true	access.token.claim
54f768e0-23c7-4431-8ce8-a1f2aa078e46	family_name	claim.name
54f768e0-23c7-4431-8ce8-a1f2aa078e46	String	jsonType.label
5736e663-c714-482c-8b84-937c6ec3e8c3	true	introspection.token.claim
5736e663-c714-482c-8b84-937c6ec3e8c3	true	userinfo.token.claim
5736e663-c714-482c-8b84-937c6ec3e8c3	birthdate	user.attribute
5736e663-c714-482c-8b84-937c6ec3e8c3	true	id.token.claim
5736e663-c714-482c-8b84-937c6ec3e8c3	true	access.token.claim
5736e663-c714-482c-8b84-937c6ec3e8c3	birthdate	claim.name
5736e663-c714-482c-8b84-937c6ec3e8c3	String	jsonType.label
5f5c944c-f89c-47d3-a07a-27b5eff31c5a	true	introspection.token.claim
5f5c944c-f89c-47d3-a07a-27b5eff31c5a	true	userinfo.token.claim
5f5c944c-f89c-47d3-a07a-27b5eff31c5a	locale	user.attribute
5f5c944c-f89c-47d3-a07a-27b5eff31c5a	true	id.token.claim
5f5c944c-f89c-47d3-a07a-27b5eff31c5a	true	access.token.claim
5f5c944c-f89c-47d3-a07a-27b5eff31c5a	locale	claim.name
5f5c944c-f89c-47d3-a07a-27b5eff31c5a	String	jsonType.label
6a104d9a-914f-4018-a262-98b5153def14	true	introspection.token.claim
6a104d9a-914f-4018-a262-98b5153def14	true	userinfo.token.claim
6a104d9a-914f-4018-a262-98b5153def14	middleName	user.attribute
6a104d9a-914f-4018-a262-98b5153def14	true	id.token.claim
6a104d9a-914f-4018-a262-98b5153def14	true	access.token.claim
6a104d9a-914f-4018-a262-98b5153def14	middle_name	claim.name
6a104d9a-914f-4018-a262-98b5153def14	String	jsonType.label
73645be4-6eef-4442-8c73-37a159e86faf	true	introspection.token.claim
73645be4-6eef-4442-8c73-37a159e86faf	true	userinfo.token.claim
73645be4-6eef-4442-8c73-37a159e86faf	profile	user.attribute
73645be4-6eef-4442-8c73-37a159e86faf	true	id.token.claim
73645be4-6eef-4442-8c73-37a159e86faf	true	access.token.claim
73645be4-6eef-4442-8c73-37a159e86faf	profile	claim.name
73645be4-6eef-4442-8c73-37a159e86faf	String	jsonType.label
7b4888a3-e8ed-4297-89df-474d097c802f	true	introspection.token.claim
7b4888a3-e8ed-4297-89df-474d097c802f	true	userinfo.token.claim
7b4888a3-e8ed-4297-89df-474d097c802f	zoneinfo	user.attribute
7b4888a3-e8ed-4297-89df-474d097c802f	true	id.token.claim
7b4888a3-e8ed-4297-89df-474d097c802f	true	access.token.claim
7b4888a3-e8ed-4297-89df-474d097c802f	zoneinfo	claim.name
7b4888a3-e8ed-4297-89df-474d097c802f	String	jsonType.label
94ab3372-f8e5-431e-a6ae-1d65601ea110	true	introspection.token.claim
94ab3372-f8e5-431e-a6ae-1d65601ea110	true	userinfo.token.claim
94ab3372-f8e5-431e-a6ae-1d65601ea110	username	user.attribute
94ab3372-f8e5-431e-a6ae-1d65601ea110	true	id.token.claim
94ab3372-f8e5-431e-a6ae-1d65601ea110	true	access.token.claim
94ab3372-f8e5-431e-a6ae-1d65601ea110	preferred_username	claim.name
94ab3372-f8e5-431e-a6ae-1d65601ea110	String	jsonType.label
c77770d0-02fa-477f-965e-dcafc2f7637c	true	introspection.token.claim
c77770d0-02fa-477f-965e-dcafc2f7637c	true	userinfo.token.claim
c77770d0-02fa-477f-965e-dcafc2f7637c	gender	user.attribute
c77770d0-02fa-477f-965e-dcafc2f7637c	true	id.token.claim
c77770d0-02fa-477f-965e-dcafc2f7637c	true	access.token.claim
c77770d0-02fa-477f-965e-dcafc2f7637c	gender	claim.name
c77770d0-02fa-477f-965e-dcafc2f7637c	String	jsonType.label
d5cf4377-a54b-43db-97b9-cd2ebff0eed4	true	introspection.token.claim
d5cf4377-a54b-43db-97b9-cd2ebff0eed4	true	userinfo.token.claim
d5cf4377-a54b-43db-97b9-cd2ebff0eed4	website	user.attribute
d5cf4377-a54b-43db-97b9-cd2ebff0eed4	true	id.token.claim
d5cf4377-a54b-43db-97b9-cd2ebff0eed4	true	access.token.claim
d5cf4377-a54b-43db-97b9-cd2ebff0eed4	website	claim.name
d5cf4377-a54b-43db-97b9-cd2ebff0eed4	String	jsonType.label
d78c2ebf-3d1b-4e11-91cb-7888a39addaa	true	introspection.token.claim
d78c2ebf-3d1b-4e11-91cb-7888a39addaa	true	userinfo.token.claim
d78c2ebf-3d1b-4e11-91cb-7888a39addaa	updatedAt	user.attribute
d78c2ebf-3d1b-4e11-91cb-7888a39addaa	true	id.token.claim
d78c2ebf-3d1b-4e11-91cb-7888a39addaa	true	access.token.claim
d78c2ebf-3d1b-4e11-91cb-7888a39addaa	updated_at	claim.name
d78c2ebf-3d1b-4e11-91cb-7888a39addaa	long	jsonType.label
1b330d9c-40c1-4bd7-b6cf-fcb638c3302d	true	introspection.token.claim
1b330d9c-40c1-4bd7-b6cf-fcb638c3302d	true	userinfo.token.claim
1b330d9c-40c1-4bd7-b6cf-fcb638c3302d	emailVerified	user.attribute
1b330d9c-40c1-4bd7-b6cf-fcb638c3302d	true	id.token.claim
1b330d9c-40c1-4bd7-b6cf-fcb638c3302d	true	access.token.claim
1b330d9c-40c1-4bd7-b6cf-fcb638c3302d	email_verified	claim.name
1b330d9c-40c1-4bd7-b6cf-fcb638c3302d	boolean	jsonType.label
b6abdf34-737f-454b-847b-e95e39137dde	true	introspection.token.claim
b6abdf34-737f-454b-847b-e95e39137dde	true	userinfo.token.claim
b6abdf34-737f-454b-847b-e95e39137dde	email	user.attribute
b6abdf34-737f-454b-847b-e95e39137dde	true	id.token.claim
b6abdf34-737f-454b-847b-e95e39137dde	true	access.token.claim
b6abdf34-737f-454b-847b-e95e39137dde	email	claim.name
b6abdf34-737f-454b-847b-e95e39137dde	String	jsonType.label
f6e03e8f-39fb-46be-9d06-c8d9cb31efdd	formatted	user.attribute.formatted
f6e03e8f-39fb-46be-9d06-c8d9cb31efdd	country	user.attribute.country
f6e03e8f-39fb-46be-9d06-c8d9cb31efdd	true	introspection.token.claim
f6e03e8f-39fb-46be-9d06-c8d9cb31efdd	postal_code	user.attribute.postal_code
f6e03e8f-39fb-46be-9d06-c8d9cb31efdd	true	userinfo.token.claim
f6e03e8f-39fb-46be-9d06-c8d9cb31efdd	street	user.attribute.street
f6e03e8f-39fb-46be-9d06-c8d9cb31efdd	true	id.token.claim
f6e03e8f-39fb-46be-9d06-c8d9cb31efdd	region	user.attribute.region
f6e03e8f-39fb-46be-9d06-c8d9cb31efdd	true	access.token.claim
f6e03e8f-39fb-46be-9d06-c8d9cb31efdd	locality	user.attribute.locality
5f74333e-655b-47b1-a7c6-20e3a80a6fb0	true	introspection.token.claim
5f74333e-655b-47b1-a7c6-20e3a80a6fb0	true	userinfo.token.claim
5f74333e-655b-47b1-a7c6-20e3a80a6fb0	phoneNumberVerified	user.attribute
5f74333e-655b-47b1-a7c6-20e3a80a6fb0	true	id.token.claim
5f74333e-655b-47b1-a7c6-20e3a80a6fb0	true	access.token.claim
5f74333e-655b-47b1-a7c6-20e3a80a6fb0	phone_number_verified	claim.name
5f74333e-655b-47b1-a7c6-20e3a80a6fb0	boolean	jsonType.label
ba44cc8c-b378-4187-b686-be259bfbf93b	true	introspection.token.claim
ba44cc8c-b378-4187-b686-be259bfbf93b	true	userinfo.token.claim
ba44cc8c-b378-4187-b686-be259bfbf93b	phoneNumber	user.attribute
ba44cc8c-b378-4187-b686-be259bfbf93b	true	id.token.claim
ba44cc8c-b378-4187-b686-be259bfbf93b	true	access.token.claim
ba44cc8c-b378-4187-b686-be259bfbf93b	phone_number	claim.name
ba44cc8c-b378-4187-b686-be259bfbf93b	String	jsonType.label
aa3bfd31-74e1-4793-a99e-96fe8270da48	true	introspection.token.claim
aa3bfd31-74e1-4793-a99e-96fe8270da48	true	multivalued
aa3bfd31-74e1-4793-a99e-96fe8270da48	foo	user.attribute
aa3bfd31-74e1-4793-a99e-96fe8270da48	true	access.token.claim
aa3bfd31-74e1-4793-a99e-96fe8270da48	realm_access.roles	claim.name
aa3bfd31-74e1-4793-a99e-96fe8270da48	String	jsonType.label
b8a50523-0db8-40cb-9562-013b231bd328	true	introspection.token.claim
b8a50523-0db8-40cb-9562-013b231bd328	true	access.token.claim
f0fcf6f3-62a1-4fec-b516-b57ef55a767f	true	introspection.token.claim
f0fcf6f3-62a1-4fec-b516-b57ef55a767f	true	multivalued
f0fcf6f3-62a1-4fec-b516-b57ef55a767f	foo	user.attribute
f0fcf6f3-62a1-4fec-b516-b57ef55a767f	true	access.token.claim
f0fcf6f3-62a1-4fec-b516-b57ef55a767f	resource_access.${client_id}.roles	claim.name
f0fcf6f3-62a1-4fec-b516-b57ef55a767f	String	jsonType.label
859b1f19-ef22-4249-8e0c-11265e2cedd5	true	introspection.token.claim
859b1f19-ef22-4249-8e0c-11265e2cedd5	true	access.token.claim
9d41e23e-13d2-4f42-932b-facf6476bee6	true	introspection.token.claim
9d41e23e-13d2-4f42-932b-facf6476bee6	true	multivalued
9d41e23e-13d2-4f42-932b-facf6476bee6	foo	user.attribute
9d41e23e-13d2-4f42-932b-facf6476bee6	true	id.token.claim
9d41e23e-13d2-4f42-932b-facf6476bee6	true	access.token.claim
9d41e23e-13d2-4f42-932b-facf6476bee6	groups	claim.name
9d41e23e-13d2-4f42-932b-facf6476bee6	String	jsonType.label
dd1ebf5c-32fd-4f25-a0ea-c0e0cf834e8f	true	introspection.token.claim
dd1ebf5c-32fd-4f25-a0ea-c0e0cf834e8f	true	userinfo.token.claim
dd1ebf5c-32fd-4f25-a0ea-c0e0cf834e8f	username	user.attribute
dd1ebf5c-32fd-4f25-a0ea-c0e0cf834e8f	true	id.token.claim
dd1ebf5c-32fd-4f25-a0ea-c0e0cf834e8f	true	access.token.claim
dd1ebf5c-32fd-4f25-a0ea-c0e0cf834e8f	upn	claim.name
dd1ebf5c-32fd-4f25-a0ea-c0e0cf834e8f	String	jsonType.label
68450db1-e90e-48f7-b305-4a903fe14fb0	true	introspection.token.claim
68450db1-e90e-48f7-b305-4a903fe14fb0	true	id.token.claim
68450db1-e90e-48f7-b305-4a903fe14fb0	true	access.token.claim
179d95b9-2f6b-477c-8854-df7b4089ff2b	AUTH_TIME	user.session.note
179d95b9-2f6b-477c-8854-df7b4089ff2b	true	introspection.token.claim
179d95b9-2f6b-477c-8854-df7b4089ff2b	true	id.token.claim
179d95b9-2f6b-477c-8854-df7b4089ff2b	true	access.token.claim
179d95b9-2f6b-477c-8854-df7b4089ff2b	auth_time	claim.name
179d95b9-2f6b-477c-8854-df7b4089ff2b	long	jsonType.label
2c6c9f3d-a2b0-4fac-8993-a31ef24eec3a	true	introspection.token.claim
2c6c9f3d-a2b0-4fac-8993-a31ef24eec3a	true	access.token.claim
8a69d488-c871-48ca-be7e-2e1ada191097	clientHost	user.session.note
8a69d488-c871-48ca-be7e-2e1ada191097	true	introspection.token.claim
8a69d488-c871-48ca-be7e-2e1ada191097	true	id.token.claim
8a69d488-c871-48ca-be7e-2e1ada191097	true	access.token.claim
8a69d488-c871-48ca-be7e-2e1ada191097	clientHost	claim.name
8a69d488-c871-48ca-be7e-2e1ada191097	String	jsonType.label
cd67005b-0b76-4381-86f4-d394029e3b52	clientAddress	user.session.note
cd67005b-0b76-4381-86f4-d394029e3b52	true	introspection.token.claim
cd67005b-0b76-4381-86f4-d394029e3b52	true	id.token.claim
cd67005b-0b76-4381-86f4-d394029e3b52	true	access.token.claim
cd67005b-0b76-4381-86f4-d394029e3b52	clientAddress	claim.name
cd67005b-0b76-4381-86f4-d394029e3b52	String	jsonType.label
e5cc6be4-63f6-4d5a-877c-e1ea2b6820c0	client_id	user.session.note
e5cc6be4-63f6-4d5a-877c-e1ea2b6820c0	true	introspection.token.claim
e5cc6be4-63f6-4d5a-877c-e1ea2b6820c0	true	id.token.claim
e5cc6be4-63f6-4d5a-877c-e1ea2b6820c0	true	access.token.claim
e5cc6be4-63f6-4d5a-877c-e1ea2b6820c0	client_id	claim.name
e5cc6be4-63f6-4d5a-877c-e1ea2b6820c0	String	jsonType.label
d4214af9-e0b8-45ca-943e-bd61bc8a95ca	true	introspection.token.claim
d4214af9-e0b8-45ca-943e-bd61bc8a95ca	true	multivalued
d4214af9-e0b8-45ca-943e-bd61bc8a95ca	true	id.token.claim
d4214af9-e0b8-45ca-943e-bd61bc8a95ca	true	access.token.claim
d4214af9-e0b8-45ca-943e-bd61bc8a95ca	organization	claim.name
d4214af9-e0b8-45ca-943e-bd61bc8a95ca	String	jsonType.label
3c29b84f-7dd3-4705-894c-1f967dd925c2	true	introspection.token.claim
3c29b84f-7dd3-4705-894c-1f967dd925c2	true	userinfo.token.claim
3c29b84f-7dd3-4705-894c-1f967dd925c2	locale	user.attribute
3c29b84f-7dd3-4705-894c-1f967dd925c2	true	id.token.claim
3c29b84f-7dd3-4705-894c-1f967dd925c2	true	access.token.claim
3c29b84f-7dd3-4705-894c-1f967dd925c2	locale	claim.name
3c29b84f-7dd3-4705-894c-1f967dd925c2	String	jsonType.label
\.


--
-- Data for Name: realm; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.realm (id, access_code_lifespan, user_action_lifespan, access_token_lifespan, account_theme, admin_theme, email_theme, enabled, events_enabled, events_expiration, login_theme, name, not_before, password_policy, registration_allowed, remember_me, reset_password_allowed, social, ssl_required, sso_idle_timeout, sso_max_lifespan, update_profile_on_soc_login, verify_email, master_admin_client, login_lifespan, internationalization_enabled, default_locale, reg_email_as_username, admin_events_enabled, admin_events_details_enabled, edit_username_allowed, otp_policy_counter, otp_policy_window, otp_policy_period, otp_policy_digits, otp_policy_alg, otp_policy_type, browser_flow, registration_flow, direct_grant_flow, reset_credentials_flow, client_auth_flow, offline_session_idle_timeout, revoke_refresh_token, access_token_life_implicit, login_with_email_allowed, duplicate_emails_allowed, docker_auth_flow, refresh_token_max_reuse, allow_user_managed_access, sso_max_lifespan_remember_me, sso_idle_timeout_remember_me, default_role, display_name) FROM stdin;
5928e5d4-c400-4150-9107-da98acace8cf	60	300	300	\N	\N	\N	t	f	0	\N	erp-realm	0	length(8) and upperCase(1) and lowerCase(1) and digits(1) and specialChars(1) and notUsername(undefined) and notEmail(undefined)	f	f	f	f	EXTERNAL	1800	36000	f	f	db6561a3-eade-43c8-aff5-28c54ee54e19	1800	f	\N	f	f	f	f	0	1	30	6	HmacSHA1	totp	509d7aad-da1f-4abd-aab1-1a7478101578	d0baeced-93df-464d-b388-18f8b2629324	34d95689-1631-4af2-b2f3-82c538c316f2	c1cc7640-d4e9-48e7-b062-aced0771c2b4	9770201c-6ffe-4089-adab-d16b13fdcfd6	2592000	f	900	t	f	b13d0e4c-0ae6-42ae-b0f3-9b10c34b2062	0	f	0	0	28e26c46-098c-4b01-8576-0d5799ac35c4	\N
331e6113-4db4-4433-997e-09db1350e12a	60	300	60	\N	\N	\N	t	f	0	\N	master	0	\N	f	f	f	f	EXTERNAL	1800	36000	f	f	4caeb1d0-bc9d-4239-a764-0237ee150cec	1800	f	\N	f	f	f	f	0	1	30	6	HmacSHA1	totp	11c99cf1-51bb-4b35-936e-08120938e064	7badefb3-ac43-43ba-8028-608c6f6438e2	acf00bd3-ff09-4e6a-96af-3fbe054f6b21	e4ba5024-be4b-49f9-9be8-7de0ec713ca3	d0aca77b-fb6b-494c-8602-c984ef78120d	2592000	f	900	t	f	193dd51a-cea0-4619-ade0-2780e330204a	0	f	0	0	6cf9ef6c-622a-4974-a502-6f878870e46a	Keycloak
\.


--
-- Data for Name: realm_attribute; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.realm_attribute (name, realm_id, value) FROM stdin;
_browser_header.contentSecurityPolicyReportOnly	331e6113-4db4-4433-997e-09db1350e12a	
_browser_header.xContentTypeOptions	331e6113-4db4-4433-997e-09db1350e12a	nosniff
_browser_header.referrerPolicy	331e6113-4db4-4433-997e-09db1350e12a	no-referrer
_browser_header.xRobotsTag	331e6113-4db4-4433-997e-09db1350e12a	none
_browser_header.xFrameOptions	331e6113-4db4-4433-997e-09db1350e12a	SAMEORIGIN
_browser_header.contentSecurityPolicy	331e6113-4db4-4433-997e-09db1350e12a	frame-src 'self'; frame-ancestors 'self'; object-src 'none';
_browser_header.strictTransportSecurity	331e6113-4db4-4433-997e-09db1350e12a	max-age=31536000; includeSubDomains
bruteForceProtected	331e6113-4db4-4433-997e-09db1350e12a	false
permanentLockout	331e6113-4db4-4433-997e-09db1350e12a	false
maxTemporaryLockouts	331e6113-4db4-4433-997e-09db1350e12a	0
bruteForceStrategy	331e6113-4db4-4433-997e-09db1350e12a	MULTIPLE
maxFailureWaitSeconds	331e6113-4db4-4433-997e-09db1350e12a	900
minimumQuickLoginWaitSeconds	331e6113-4db4-4433-997e-09db1350e12a	60
waitIncrementSeconds	331e6113-4db4-4433-997e-09db1350e12a	60
quickLoginCheckMilliSeconds	331e6113-4db4-4433-997e-09db1350e12a	1000
maxDeltaTimeSeconds	331e6113-4db4-4433-997e-09db1350e12a	43200
failureFactor	331e6113-4db4-4433-997e-09db1350e12a	30
maxSecondaryAuthFailures	331e6113-4db4-4433-997e-09db1350e12a	0
realmReusableOtpCode	331e6113-4db4-4433-997e-09db1350e12a	false
firstBrokerLoginFlowId	331e6113-4db4-4433-997e-09db1350e12a	306af93f-cb5f-49a9-9533-947f7df994b3
displayNameHtml	331e6113-4db4-4433-997e-09db1350e12a	<div class="kc-logo-text"><span>Keycloak</span></div>
defaultSignatureAlgorithm	331e6113-4db4-4433-997e-09db1350e12a	RS256
offlineSessionMaxLifespanEnabled	331e6113-4db4-4433-997e-09db1350e12a	false
offlineSessionMaxLifespan	331e6113-4db4-4433-997e-09db1350e12a	5184000
_browser_header.contentSecurityPolicyReportOnly	5928e5d4-c400-4150-9107-da98acace8cf	
_browser_header.xContentTypeOptions	5928e5d4-c400-4150-9107-da98acace8cf	nosniff
_browser_header.referrerPolicy	5928e5d4-c400-4150-9107-da98acace8cf	no-referrer
_browser_header.xRobotsTag	5928e5d4-c400-4150-9107-da98acace8cf	none
_browser_header.xFrameOptions	5928e5d4-c400-4150-9107-da98acace8cf	SAMEORIGIN
_browser_header.contentSecurityPolicy	5928e5d4-c400-4150-9107-da98acace8cf	frame-src 'self'; frame-ancestors 'self'; object-src 'none';
_browser_header.strictTransportSecurity	5928e5d4-c400-4150-9107-da98acace8cf	max-age=31536000; includeSubDomains
permanentLockout	5928e5d4-c400-4150-9107-da98acace8cf	false
maxTemporaryLockouts	5928e5d4-c400-4150-9107-da98acace8cf	0
bruteForceStrategy	5928e5d4-c400-4150-9107-da98acace8cf	MULTIPLE
maxFailureWaitSeconds	5928e5d4-c400-4150-9107-da98acace8cf	900
minimumQuickLoginWaitSeconds	5928e5d4-c400-4150-9107-da98acace8cf	60
waitIncrementSeconds	5928e5d4-c400-4150-9107-da98acace8cf	60
quickLoginCheckMilliSeconds	5928e5d4-c400-4150-9107-da98acace8cf	1000
maxDeltaTimeSeconds	5928e5d4-c400-4150-9107-da98acace8cf	43200
realmReusableOtpCode	5928e5d4-c400-4150-9107-da98acace8cf	false
defaultSignatureAlgorithm	5928e5d4-c400-4150-9107-da98acace8cf	RS256
offlineSessionMaxLifespanEnabled	5928e5d4-c400-4150-9107-da98acace8cf	false
offlineSessionMaxLifespan	5928e5d4-c400-4150-9107-da98acace8cf	5184000
actionTokenGeneratedByAdminLifespan	5928e5d4-c400-4150-9107-da98acace8cf	43200
actionTokenGeneratedByUserLifespan	5928e5d4-c400-4150-9107-da98acace8cf	300
oauth2DeviceCodeLifespan	5928e5d4-c400-4150-9107-da98acace8cf	600
oauth2DevicePollingInterval	5928e5d4-c400-4150-9107-da98acace8cf	5
webAuthnPolicyRpEntityName	5928e5d4-c400-4150-9107-da98acace8cf	keycloak
webAuthnPolicySignatureAlgorithms	5928e5d4-c400-4150-9107-da98acace8cf	ES256,RS256
webAuthnPolicyRpId	5928e5d4-c400-4150-9107-da98acace8cf	
webAuthnPolicyAttestationConveyancePreference	5928e5d4-c400-4150-9107-da98acace8cf	not specified
webAuthnPolicyAuthenticatorAttachment	5928e5d4-c400-4150-9107-da98acace8cf	not specified
webAuthnPolicyResidentKey	5928e5d4-c400-4150-9107-da98acace8cf	not specified
webAuthnPolicyRequireResidentKey	5928e5d4-c400-4150-9107-da98acace8cf	not specified
webAuthnPolicyUserVerificationRequirement	5928e5d4-c400-4150-9107-da98acace8cf	not specified
webAuthnPolicyCreateTimeout	5928e5d4-c400-4150-9107-da98acace8cf	0
webAuthnPolicyAvoidSameAuthenticatorRegister	5928e5d4-c400-4150-9107-da98acace8cf	false
webAuthnPolicyRpEntityNamePasswordless	5928e5d4-c400-4150-9107-da98acace8cf	keycloak
webAuthnPolicySignatureAlgorithmsPasswordless	5928e5d4-c400-4150-9107-da98acace8cf	ES256,RS256
webAuthnPolicyRpIdPasswordless	5928e5d4-c400-4150-9107-da98acace8cf	
webAuthnPolicyAttestationConveyancePreferencePasswordless	5928e5d4-c400-4150-9107-da98acace8cf	not specified
webAuthnPolicyAuthenticatorAttachmentPasswordless	5928e5d4-c400-4150-9107-da98acace8cf	not specified
webAuthnPolicyResidentKeyPasswordless	5928e5d4-c400-4150-9107-da98acace8cf	required
webAuthnPolicyRequireResidentKeyPasswordless	5928e5d4-c400-4150-9107-da98acace8cf	not specified
webAuthnPolicyUserVerificationRequirementPasswordless	5928e5d4-c400-4150-9107-da98acace8cf	required
webAuthnPolicyCreateTimeoutPasswordless	5928e5d4-c400-4150-9107-da98acace8cf	0
webAuthnPolicyAvoidSameAuthenticatorRegisterPasswordless	5928e5d4-c400-4150-9107-da98acace8cf	false
cibaBackchannelTokenDeliveryMode	5928e5d4-c400-4150-9107-da98acace8cf	poll
cibaExpiresIn	5928e5d4-c400-4150-9107-da98acace8cf	120
cibaInterval	5928e5d4-c400-4150-9107-da98acace8cf	5
cibaAuthRequestedUserHint	5928e5d4-c400-4150-9107-da98acace8cf	login_hint
parRequestUriLifespan	5928e5d4-c400-4150-9107-da98acace8cf	60
firstBrokerLoginFlowId	5928e5d4-c400-4150-9107-da98acace8cf	e6b61eb8-2edd-45b8-b81a-23cd657e397d
organizationsEnabled	5928e5d4-c400-4150-9107-da98acace8cf	false
scimApiEnabled	5928e5d4-c400-4150-9107-da98acace8cf	false
adminPermissionsEnabled	5928e5d4-c400-4150-9107-da98acace8cf	false
verifiableCredentialsEnabled	5928e5d4-c400-4150-9107-da98acace8cf	false
clientSessionIdleTimeout	5928e5d4-c400-4150-9107-da98acace8cf	0
clientSessionMaxLifespan	5928e5d4-c400-4150-9107-da98acace8cf	0
clientOfflineSessionIdleTimeout	5928e5d4-c400-4150-9107-da98acace8cf	0
clientOfflineSessionMaxLifespan	5928e5d4-c400-4150-9107-da98acace8cf	0
client-policies.profiles	5928e5d4-c400-4150-9107-da98acace8cf	{"profiles":[]}
client-policies.policies	5928e5d4-c400-4150-9107-da98acace8cf	{"policies":[]}
bruteForceProtected	5928e5d4-c400-4150-9107-da98acace8cf	true
failureFactor	5928e5d4-c400-4150-9107-da98acace8cf	2
maxSecondaryAuthFailures	5928e5d4-c400-4150-9107-da98acace8cf	3
\.


--
-- Data for Name: realm_default_groups; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.realm_default_groups (realm_id, group_id) FROM stdin;
\.


--
-- Data for Name: realm_enabled_event_types; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.realm_enabled_event_types (realm_id, value) FROM stdin;
\.


--
-- Data for Name: realm_events_listeners; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.realm_events_listeners (realm_id, value) FROM stdin;
331e6113-4db4-4433-997e-09db1350e12a	jboss-logging
5928e5d4-c400-4150-9107-da98acace8cf	jboss-logging
\.


--
-- Data for Name: realm_localizations; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.realm_localizations (realm_id, locale, texts) FROM stdin;
\.


--
-- Data for Name: realm_required_credential; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.realm_required_credential (type, form_label, input, secret, realm_id) FROM stdin;
password	password	t	t	331e6113-4db4-4433-997e-09db1350e12a
password	password	t	t	5928e5d4-c400-4150-9107-da98acace8cf
\.


--
-- Data for Name: realm_smtp_config; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.realm_smtp_config (realm_id, value, name) FROM stdin;
\.


--
-- Data for Name: realm_supported_locales; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.realm_supported_locales (realm_id, value) FROM stdin;
\.


--
-- Data for Name: redirect_uris; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.redirect_uris (client_id, value) FROM stdin;
02c5d277-7643-45c6-a008-1bba899b38ef	/realms/master/account/*
00b14034-0863-4908-85f7-81849f8af952	/realms/master/account/*
a7ac4e8e-3117-44a8-95b0-f02c71ded253	/admin/master/console/*
5acab47a-ebce-406b-aaea-a826b37a7a67	/realms/erp-realm/account/*
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	/realms/erp-realm/account/*
02921f33-7315-4da6-aa49-bb63211e78df	/admin/erp-realm/console/*
9944fc9f-2d6f-4ae5-bb98-75124c770501	http://localhost:*
\.


--
-- Data for Name: required_action_config; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.required_action_config (required_action_id, value, name) FROM stdin;
\.


--
-- Data for Name: required_action_provider; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.required_action_provider (id, alias, name, realm_id, enabled, default_action, provider_id, priority) FROM stdin;
893d3b1a-1311-4e7c-9961-0c3494907637	VERIFY_EMAIL	Verify Email	331e6113-4db4-4433-997e-09db1350e12a	t	f	VERIFY_EMAIL	50
b0f8ef37-ad25-40a9-b070-b484c5b94f1e	UPDATE_PROFILE	Update Profile	331e6113-4db4-4433-997e-09db1350e12a	t	f	UPDATE_PROFILE	40
faacf664-f699-4a50-ba22-8a442167c325	UPDATE_PASSWORD	Update Password	331e6113-4db4-4433-997e-09db1350e12a	t	f	UPDATE_PASSWORD	57
d6c1dee5-709c-4063-9a4b-d8f6d9945f26	TERMS_AND_CONDITIONS	Terms and Conditions	331e6113-4db4-4433-997e-09db1350e12a	f	f	TERMS_AND_CONDITIONS	20
b12bd84b-617c-4dc0-b726-ba27b7e67f47	delete_account	Delete Account	331e6113-4db4-4433-997e-09db1350e12a	f	f	delete_account	60
9d4f92c7-3c3f-4e19-be50-46d7f6e46488	delete_credential	Delete Credential	331e6113-4db4-4433-997e-09db1350e12a	t	f	delete_credential	110
af014631-25f3-48ce-9669-8b501c4e57b5	update_user_locale	Update User Locale	331e6113-4db4-4433-997e-09db1350e12a	t	f	update_user_locale	1000
59417eae-5d4b-4f43-8ada-1d1e849f399b	UPDATE_EMAIL	Update Email	331e6113-4db4-4433-997e-09db1350e12a	f	f	UPDATE_EMAIL	70
0a4fe20e-a30c-44a9-99f6-1a8fc2b175c6	CONFIGURE_RECOVERY_AUTHN_CODES	Recovery Authentication Codes	331e6113-4db4-4433-997e-09db1350e12a	t	f	CONFIGURE_RECOVERY_AUTHN_CODES	130
3641944c-bb05-4176-8335-d66f5c020b2f	webauthn-register	Webauthn Register	331e6113-4db4-4433-997e-09db1350e12a	t	f	webauthn-register	80
fb811dbf-91db-4602-9266-1ce150a67f2a	webauthn-register-passwordless	Webauthn Register Passwordless	331e6113-4db4-4433-997e-09db1350e12a	t	f	webauthn-register-passwordless	90
7cf75182-d4a8-40ce-8c8a-273169d8be57	VERIFY_PROFILE	Verify Profile	331e6113-4db4-4433-997e-09db1350e12a	t	f	VERIFY_PROFILE	100
cab1aff6-3201-4b94-b158-4cf46cbfaa42	idp_link	Linking Identity Provider	331e6113-4db4-4433-997e-09db1350e12a	t	f	idp_link	120
a0779fa4-7717-4275-9ce6-c67d8b13d2f4	VERIFY_EMAIL	Verify Email	5928e5d4-c400-4150-9107-da98acace8cf	t	f	VERIFY_EMAIL	50
db90bf6d-d8a5-43a8-83a6-bb19108da793	UPDATE_PROFILE	Update Profile	5928e5d4-c400-4150-9107-da98acace8cf	t	f	UPDATE_PROFILE	40
2065a7b8-58e5-4486-881d-56b309aceb0e	CONFIGURE_TOTP	Configure OTP	5928e5d4-c400-4150-9107-da98acace8cf	t	f	CONFIGURE_TOTP	54
9b5fa373-528c-4024-a73f-1af54e6588c4	UPDATE_PASSWORD	Update Password	5928e5d4-c400-4150-9107-da98acace8cf	t	f	UPDATE_PASSWORD	57
8aba57fb-b0d2-4a3b-a414-10ff33f5964c	TERMS_AND_CONDITIONS	Terms and Conditions	5928e5d4-c400-4150-9107-da98acace8cf	f	f	TERMS_AND_CONDITIONS	20
c998a594-daa7-4c6b-85f6-90ec00f6ac66	delete_account	Delete Account	5928e5d4-c400-4150-9107-da98acace8cf	f	f	delete_account	60
dd1a78c0-1e29-40aa-b61d-9c1ca444c0a6	delete_credential	Delete Credential	5928e5d4-c400-4150-9107-da98acace8cf	t	f	delete_credential	110
e9b847a6-4863-445c-9392-de78a022ed96	update_user_locale	Update User Locale	5928e5d4-c400-4150-9107-da98acace8cf	t	f	update_user_locale	1000
236bf98c-3119-4109-a880-b5a134f6a6d1	UPDATE_EMAIL	Update Email	5928e5d4-c400-4150-9107-da98acace8cf	f	f	UPDATE_EMAIL	70
bb936e4b-38d8-464d-8a91-1a127d3de5d1	CONFIGURE_RECOVERY_AUTHN_CODES	Recovery Authentication Codes	5928e5d4-c400-4150-9107-da98acace8cf	t	f	CONFIGURE_RECOVERY_AUTHN_CODES	130
29ca888c-090a-4e09-b5cd-9cea6929081f	webauthn-register	Webauthn Register	5928e5d4-c400-4150-9107-da98acace8cf	t	f	webauthn-register	80
3443d5fc-a616-45d0-83fe-4a804ec1f52d	webauthn-register-passwordless	Webauthn Register Passwordless	5928e5d4-c400-4150-9107-da98acace8cf	t	f	webauthn-register-passwordless	90
e2c73cb1-4745-4fd6-a3ad-8effc0c33fec	VERIFY_PROFILE	Verify Profile	5928e5d4-c400-4150-9107-da98acace8cf	t	f	VERIFY_PROFILE	100
8259daf8-940d-4492-b1ae-eda217fd97ad	idp_link	Linking Identity Provider	5928e5d4-c400-4150-9107-da98acace8cf	t	f	idp_link	120
bade9e74-9846-4b61-84f4-64a3b62feca6	CONFIGURE_TOTP	Configure OTP	331e6113-4db4-4433-997e-09db1350e12a	f	f	CONFIGURE_TOTP	54
\.


--
-- Data for Name: resource_attribute; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.resource_attribute (id, name, value, resource_id) FROM stdin;
\.


--
-- Data for Name: resource_policy; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.resource_policy (resource_id, policy_id) FROM stdin;
\.


--
-- Data for Name: resource_scope; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.resource_scope (resource_id, scope_id) FROM stdin;
\.


--
-- Data for Name: resource_server; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.resource_server (id, allow_rs_remote_mgmt, policy_enforce_mode, decision_strategy) FROM stdin;
\.


--
-- Data for Name: resource_server_perm_ticket; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.resource_server_perm_ticket (id, owner, requester, created_timestamp, granted_timestamp, resource_id, scope_id, resource_server_id, policy_id) FROM stdin;
\.


--
-- Data for Name: resource_server_policy; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.resource_server_policy (id, name, description, type, decision_strategy, logic, resource_server_id, owner) FROM stdin;
\.


--
-- Data for Name: resource_server_resource; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.resource_server_resource (id, name, type, icon_uri, owner, resource_server_id, owner_managed_access, display_name) FROM stdin;
\.


--
-- Data for Name: resource_server_scope; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.resource_server_scope (id, name, icon_uri, resource_server_id, display_name) FROM stdin;
\.


--
-- Data for Name: resource_uris; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.resource_uris (resource_id, value) FROM stdin;
\.


--
-- Data for Name: revoked_token; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.revoked_token (id, expire) FROM stdin;
\.


--
-- Data for Name: role_attribute; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.role_attribute (id, role_id, name, value) FROM stdin;
\.


--
-- Data for Name: root_auth_session; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.root_auth_session (id, realm_id, "timestamp", version) FROM stdin;
\.


--
-- Data for Name: scope_mapping; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.scope_mapping (client_id, role_id) FROM stdin;
00b14034-0863-4908-85f7-81849f8af952	7437daf7-f05d-42ec-84e4-e9ea47029534
00b14034-0863-4908-85f7-81849f8af952	0e3782ab-601b-42e1-ac5a-8666e6c7a872
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	4d9472be-ba3b-475c-a64a-5b49404bf4ff
f85bd9aa-5ee7-42d4-adce-fdb72f28fdfe	9ff03eea-be92-48e4-a780-af4078238a0a
\.


--
-- Data for Name: scope_policy; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.scope_policy (scope_id, policy_id) FROM stdin;
\.


--
-- Data for Name: server_config; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.server_config (server_config_key, value, version) FROM stdin;
\.


--
-- Data for Name: single_use_object; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.single_use_object (id, notes, expire) FROM stdin;
\.


--
-- Data for Name: user_attribute; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.user_attribute (name, value, user_id, id, long_value_hash, long_value_hash_lower_case, long_value) FROM stdin;
is_temporary_admin	true	cbbffc68-782b-4fe9-8df5-9af0b51dac5a	91891e04-f074-47aa-9715-6ca62c91835a	\N	\N	\N
\.


--
-- Data for Name: user_consent; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.user_consent (id, client_id, user_id, created_date, last_updated_date, client_storage_provider, external_client_id) FROM stdin;
\.


--
-- Data for Name: user_consent_client_scope; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.user_consent_client_scope (user_consent_id, scope_id, parameter) FROM stdin;
\.


--
-- Data for Name: user_entity; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.user_entity (id, email, email_constraint, email_verified, enabled, federation_link, first_name, last_name, realm_id, username, created_timestamp, service_account_client_link, not_before, last_modified_timestamp) FROM stdin;
cbbffc68-782b-4fe9-8df5-9af0b51dac5a	\N	5b183284-dc79-4daf-8607-27f6e2d15661	f	t	\N	\N	\N	331e6113-4db4-4433-997e-09db1350e12a	admin	1792569178601	\N	0	1792569178601
d0fd4cdb-45a8-4033-9baa-78433f03b8d9	tulalit053@gmail.com	tulalit053@gmail.com	t	t	\N	and	m	5928e5d4-c400-4150-9107-da98acace8cf	test_admin	1792569999428	\N	0	1792569999428
fa016850-0fe4-4927-8d04-1909b6ae1414	budi.santoso@contoh.com	budi.santoso@contoh.com	t	t	\N	Budi Santoso	santoso	5928e5d4-c400-4150-9107-da98acace8cf	budi.santoso	1792639148339	\N	0	1792639148339
7660c2e6-a59f-4598-9c3d-05b7101f7c74	staff@majujaya.com	staff@majujaya.com	t	t	\N	staff	finana	5928e5d4-c400-4150-9107-da98acace8cf	staff.finance	1792727165233	\N	0	1792727165233
b525b1f0-73bf-493b-9232-8fdf59a01651	dewi.hr@jaya.com	dewi.hr@jaya.com	t	t	\N	dewi	hr	5928e5d4-c400-4150-9107-da98acace8cf	dewi.hr	1792742531035	\N	0	1792742531035
\.


--
-- Data for Name: user_federation_config; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.user_federation_config (user_federation_provider_id, value, name) FROM stdin;
\.


--
-- Data for Name: user_federation_mapper; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.user_federation_mapper (id, name, federation_provider_id, federation_mapper_type, realm_id) FROM stdin;
\.


--
-- Data for Name: user_federation_mapper_config; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.user_federation_mapper_config (user_federation_mapper_id, value, name) FROM stdin;
\.


--
-- Data for Name: user_federation_provider; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.user_federation_provider (id, changed_sync_period, display_name, full_sync_period, last_sync, priority, provider_name, realm_id) FROM stdin;
\.


--
-- Data for Name: user_group_membership; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.user_group_membership (group_id, user_id, membership_type) FROM stdin;
\.


--
-- Data for Name: user_required_action; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.user_required_action (user_id, required_action) FROM stdin;
\.


--
-- Data for Name: user_role_mapping; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.user_role_mapping (role_id, user_id) FROM stdin;
6cf9ef6c-622a-4974-a502-6f878870e46a	cbbffc68-782b-4fe9-8df5-9af0b51dac5a
0cc3385a-ce0b-4f1b-a2b2-b2fdd3539661	cbbffc68-782b-4fe9-8df5-9af0b51dac5a
28e26c46-098c-4b01-8576-0d5799ac35c4	d0fd4cdb-45a8-4033-9baa-78433f03b8d9
28e26c46-098c-4b01-8576-0d5799ac35c4	fa016850-0fe4-4927-8d04-1909b6ae1414
4bd98669-ef63-48e8-b3b4-de640fc21203	fa016850-0fe4-4927-8d04-1909b6ae1414
1c7b5d9f-36d2-4558-b0e3-d68d664107ce	fa016850-0fe4-4927-8d04-1909b6ae1414
28e26c46-098c-4b01-8576-0d5799ac35c4	7660c2e6-a59f-4598-9c3d-05b7101f7c74
28e26c46-098c-4b01-8576-0d5799ac35c4	b525b1f0-73bf-493b-9232-8fdf59a01651
\.


--
-- Data for Name: user_ver_credential; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.user_ver_credential (id, client_scope_id, user_id, revision, created_date, updated_date, user_attributes, version) FROM stdin;
\.


--
-- Data for Name: web_origins; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.web_origins (client_id, value) FROM stdin;
a7ac4e8e-3117-44a8-95b0-f02c71ded253	+
02921f33-7315-4da6-aa49-bb63211e78df	+
9944fc9f-2d6f-4ae5-bb98-75124c770501	*
\.


--
-- Data for Name: workflow_state; Type: TABLE DATA; Schema: schema_keycloak; Owner: postgres
--

COPY schema_keycloak.workflow_state (execution_id, resource_id, workflow_id, resource_type, scheduled_step_id, scheduled_step_timestamp) FROM stdin;
\.


--
-- Name: crm_lead_history_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.crm_lead_history_history_id_seq', 1, false);


--
-- Name: crm_lead_source_lead_source_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.crm_lead_source_lead_source_id_seq', 1, false);


--
-- Name: adm_log_audit_dlog_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_log_audit_dlog_id_seq', 1, false);


--
-- Name: adm_log_login_log_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_log_login_log_id_seq', 1, true);


--
-- Name: adm_mst_application_dmap_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_mst_application_dmap_id_seq', 7, true);


--
-- Name: adm_mst_company_application_dmca_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_mst_company_application_dmca_id_seq', 10, true);


--
-- Name: adm_mst_company_dmc_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_mst_company_dmc_id_seq', 2, true);


--
-- Name: adm_mst_company_module_dmcm_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_mst_company_module_dmcm_id_seq', 1, false);


--
-- Name: adm_mst_menu_temp_dmmt_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_mst_menu_temp_dmmt_id_seq', 1, false);


--
-- Name: adm_mst_role_menu_dmrm_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_mst_role_menu_dmrm_id_seq', 62, true);


--
-- Name: adm_mst_role_menu_temp_dmrmt_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_mst_role_menu_temp_dmrmt_id_seq', 1, false);


--
-- Name: adm_mst_role_temp_dmrt_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_mst_role_temp_dmrt_id_seq', 1, false);


--
-- Name: adm_mst_user_application_dmuapp_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_mst_user_application_dmuapp_id_seq', 11, true);


--
-- Name: adm_mst_user_application_temp_dmuat_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_mst_user_application_temp_dmuat_id_seq', 1, false);


--
-- Name: adm_mst_user_menu_temp_dmumt_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_mst_user_menu_temp_dmumt_id_seq', 1, false);


--
-- Name: adm_mst_user_role_dmur_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_mst_user_role_dmur_id_seq', 1, false);


--
-- Name: adm_sec_user_pass_recov_dsup_id_seq; Type: SEQUENCE SET; Schema: schema_admin; Owner: postgres
--

SELECT pg_catalog.setval('schema_admin.adm_sec_user_pass_recov_dsup_id_seq', 1, false);


--
-- Name: crm_activity_activity_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.crm_activity_activity_id_seq', 16, true);


--
-- Name: crm_activity_type_activity_type_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.crm_activity_type_activity_type_id_seq', 10, true);


--
-- Name: crm_competitor_competitor_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.crm_competitor_competitor_id_seq', 1, false);


--
-- Name: crm_interaction_log_log_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.crm_interaction_log_log_id_seq', 21, true);


--
-- Name: crm_lead_history_history_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.crm_lead_history_history_id_seq', 8, true);


--
-- Name: crm_lead_lead_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.crm_lead_lead_id_seq', 17, true);


--
-- Name: crm_lead_source_lead_source_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.crm_lead_source_lead_source_id_seq', 6, true);


--
-- Name: crm_lost_reason_lost_reason_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.crm_lost_reason_lost_reason_id_seq', 7, true);


--
-- Name: crm_monthly_target_target_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.crm_monthly_target_target_id_seq', 1, false);


--
-- Name: crm_stage_stage_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.crm_stage_stage_id_seq', 9, true);


--
-- Name: crm_ticket_conversations_conversation_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.crm_ticket_conversations_conversation_id_seq', 1, true);


--
-- Name: crm_tickets_ticket_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.crm_tickets_ticket_id_seq', 1, true);


--
-- Name: hr_employee_employee_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.hr_employee_employee_id_seq', 4, true);


--
-- Name: hr_job_job_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.hr_job_job_id_seq', 3, true);


--
-- Name: ir_attachment_attachment_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.ir_attachment_attachment_id_seq', 1, false);


--
-- Name: mail_message_message_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.mail_message_message_id_seq', 1, false);


--
-- Name: res_currency_currency_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.res_currency_currency_id_seq', 2, true);


--
-- Name: res_partner_category_category_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.res_partner_category_category_id_seq', 3, true);


--
-- Name: res_partner_contact_contact_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.res_partner_contact_contact_id_seq', 5, true);


--
-- Name: res_partner_partner_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.res_partner_partner_id_seq', 4, true);


--
-- Name: res_users_user_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.res_users_user_id_seq', 4, true);


--
-- Name: sales_targets_target_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.sales_targets_target_id_seq', 2, true);


--
-- Name: sales_team_team_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.sales_team_team_id_seq', 4, true);


--
-- Name: utm_campaign_campaign_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.utm_campaign_campaign_id_seq', 5, true);


--
-- Name: utm_medium_medium_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.utm_medium_medium_id_seq', 5, true);


--
-- Name: utm_source_source_id_seq; Type: SEQUENCE SET; Schema: schema_crm; Owner: postgres
--

SELECT pg_catalog.setval('schema_crm.utm_source_source_id_seq', 5, true);


--
-- Name: hr_log_salary_change_dlog_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_log_salary_change_dlog_id_seq', 1, false);


--
-- Name: hr_mst_approval_flow_daflow_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_approval_flow_daflow_id_seq', 1, false);


--
-- Name: hr_mst_attendance_rule_datt_rule_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_attendance_rule_datt_rule_id_seq', 2, true);


--
-- Name: hr_mst_bpjs_setting_dbpjs_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_bpjs_setting_dbpjs_id_seq', 3, true);


--
-- Name: hr_mst_company_config_dcomp_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_company_config_dcomp_id_seq', 2, true);


--
-- Name: hr_mst_department_dmdep_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_department_dmdep_id_seq', 1, false);


--
-- Name: hr_mst_employee_dmemp_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_employee_dmemp_id_seq', 7, true);


--
-- Name: hr_mst_employee_payroll_config_depc_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_employee_payroll_config_depc_id_seq', 2, true);


--
-- Name: hr_mst_employee_tax_detax_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_employee_tax_detax_id_seq', 2, true);


--
-- Name: hr_mst_formula_dform_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_formula_dform_id_seq', 3, true);


--
-- Name: hr_mst_holiday_dmhol_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_holiday_dmhol_id_seq', 1, false);


--
-- Name: hr_mst_job_grade_dgrade_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_job_grade_dgrade_id_seq', 4, true);


--
-- Name: hr_mst_leave_type_dmlty_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_leave_type_dmlty_id_seq', 1, false);


--
-- Name: hr_mst_loan_type_dloant_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_loan_type_dloant_id_seq', 2, true);


--
-- Name: hr_mst_payroll_period_dper_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_payroll_period_dper_id_seq', 3, true);


--
-- Name: hr_mst_payroll_rule_drule_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_payroll_rule_drule_id_seq', 1, false);


--
-- Name: hr_mst_position_dmpos_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_position_dmpos_id_seq', 1, false);


--
-- Name: hr_mst_ptkp_dptkp_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_ptkp_dptkp_id_seq', 8, true);


--
-- Name: hr_mst_salary_component_dmsc_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_salary_component_dmsc_id_seq', 1, false);


--
-- Name: hr_mst_shift_dshift_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_shift_dshift_id_seq', 1, false);


--
-- Name: hr_mst_tax_rate_dtax_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_mst_tax_rate_dtax_id_seq', 1, false);


--
-- Name: hr_txn_approval_dapp_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_approval_dapp_id_seq', 1, false);


--
-- Name: hr_txn_attendance_dmatn_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_attendance_dmatn_id_seq', 1, false);


--
-- Name: hr_txn_career_history_dmcar_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_career_history_dmcar_id_seq', 1, false);


--
-- Name: hr_txn_contract_dmcon_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_contract_dmcon_id_seq', 1, false);


--
-- Name: hr_txn_document_dmdoc_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_document_dmdoc_id_seq', 1, false);


--
-- Name: hr_txn_employee_payroll_rule_depr_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_employee_payroll_rule_depr_id_seq', 1, false);


--
-- Name: hr_txn_employee_salary_detail_dmsald_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_employee_salary_detail_dmsald_id_seq', 1, false);


--
-- Name: hr_txn_employee_salary_dmsal_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_employee_salary_dmsal_id_seq', 6, true);


--
-- Name: hr_txn_employee_shift_deshift_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_employee_shift_deshift_id_seq', 1, false);


--
-- Name: hr_txn_leave_balance_dmlbal_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_leave_balance_dmlbal_id_seq', 1, false);


--
-- Name: hr_txn_leave_request_dmlreq_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_leave_request_dmlreq_id_seq', 1, false);


--
-- Name: hr_txn_loan_dmlon_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_loan_dmlon_id_seq', 1, false);


--
-- Name: hr_txn_overtime_dmovt_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_overtime_dmovt_id_seq', 1, false);


--
-- Name: hr_txn_payslip_dmps_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_payslip_dmps_id_seq', 2, true);


--
-- Name: hr_txn_payslip_line_dmpsl_id_seq; Type: SEQUENCE SET; Schema: schema_hrd; Owner: postgres
--

SELECT pg_catalog.setval('schema_hrd.hr_txn_payslip_line_dmpsl_id_seq', 4, true);


--
-- Name: crm_lead_history crm_lead_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_lead_history
    ADD CONSTRAINT crm_lead_history_pkey PRIMARY KEY (history_id);


--
-- Name: crm_lead_source crm_lead_source_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_lead_source
    ADD CONSTRAINT crm_lead_source_pkey PRIMARY KEY (lead_source_id);


--
-- Name: crm_lead_source uk56etc1vmv2ilx3od8pmxd4smv; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_lead_source
    ADD CONSTRAINT uk56etc1vmv2ilx3od8pmxd4smv UNIQUE (name);


--
-- Name: adm_log_audit adm_log_audit_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_log_audit
    ADD CONSTRAINT adm_log_audit_pk PRIMARY KEY (dlog_id);


--
-- Name: adm_log_login adm_log_login_pkey; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_log_login
    ADD CONSTRAINT adm_log_login_pkey PRIMARY KEY (log_id);


--
-- Name: adm_mst_application adm_mst_application_dmap_application_code_key; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_application
    ADD CONSTRAINT adm_mst_application_dmap_application_code_key UNIQUE (dmap_application_code);


--
-- Name: adm_mst_application adm_mst_application_pkey; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_application
    ADD CONSTRAINT adm_mst_application_pkey PRIMARY KEY (dmap_id);


--
-- Name: adm_mst_company_application adm_mst_company_application_pkey; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_company_application
    ADD CONSTRAINT adm_mst_company_application_pkey PRIMARY KEY (dmca_id);


--
-- Name: adm_mst_company_module adm_mst_company_module_pkey; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_company_module
    ADD CONSTRAINT adm_mst_company_module_pkey PRIMARY KEY (dmcm_id);


--
-- Name: adm_mst_user_role adm_mst_user_role_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_role
    ADD CONSTRAINT adm_mst_user_role_pk PRIMARY KEY (dmur_id);


--
-- Name: adm_mst_user_role adm_mst_user_role_unique; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_role
    ADD CONSTRAINT adm_mst_user_role_unique UNIQUE (dmur_user_id, dmur_role_id);


--
-- Name: adm_mst_branch dge_mst_branch_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_branch
    ADD CONSTRAINT dge_mst_branch_pk PRIMARY KEY (dmbra_id);


--
-- Name: adm_mst_company dge_mst_company_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_company
    ADD CONSTRAINT dge_mst_company_pk PRIMARY KEY (dmc_id);


--
-- Name: adm_mst_currency dge_mst_currency_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_currency
    ADD CONSTRAINT dge_mst_currency_pk PRIMARY KEY (dmcur_id);


--
-- Name: adm_mst_menu dge_mst_menu_dmmenu_code_key; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_menu
    ADD CONSTRAINT dge_mst_menu_dmmenu_code_key UNIQUE (dmmenu_code);


--
-- Name: adm_mst_menu dge_mst_menu_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_menu
    ADD CONSTRAINT dge_mst_menu_pk PRIMARY KEY (dmmenu_id);


--
-- Name: adm_mst_menu_temp dge_mst_menu_temp_dmmt_code_key; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_menu_temp
    ADD CONSTRAINT dge_mst_menu_temp_dmmt_code_key UNIQUE (dmmt_code);


--
-- Name: adm_mst_menu_temp dge_mst_menu_temp_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_menu_temp
    ADD CONSTRAINT dge_mst_menu_temp_pk PRIMARY KEY (dmmt_id);


--
-- Name: adm_mst_regional dge_mst_regional_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_regional
    ADD CONSTRAINT dge_mst_regional_pk PRIMARY KEY (dmreg_id);


--
-- Name: adm_mst_role_menu dge_mst_role_menu_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_role_menu
    ADD CONSTRAINT dge_mst_role_menu_pk PRIMARY KEY (dmrm_id);


--
-- Name: adm_mst_role_menu_temp dge_mst_role_menu_temp_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_role_menu_temp
    ADD CONSTRAINT dge_mst_role_menu_temp_pk PRIMARY KEY (dmrmt_id);


--
-- Name: adm_mst_role_menu dge_mst_role_menu_unique; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_role_menu
    ADD CONSTRAINT dge_mst_role_menu_unique UNIQUE (dmrm_role_id, dmrm_menu_id);


--
-- Name: adm_mst_role dge_mst_role_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_role
    ADD CONSTRAINT dge_mst_role_pk PRIMARY KEY (dmrole_id);


--
-- Name: adm_mst_role_temp dge_mst_role_temp_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_role_temp
    ADD CONSTRAINT dge_mst_role_temp_pk PRIMARY KEY (dmrt_id);


--
-- Name: adm_mst_sub_branch dge_mst_sub_branch_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_sub_branch
    ADD CONSTRAINT dge_mst_sub_branch_pk PRIMARY KEY (dmsbr_id);


--
-- Name: adm_mst_user_application dge_mst_user_application_dmuapp_username_key; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_application
    ADD CONSTRAINT dge_mst_user_application_dmuapp_username_key UNIQUE (dmuapp_username);


--
-- Name: adm_mst_user_application dge_mst_user_application_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_application
    ADD CONSTRAINT dge_mst_user_application_pk PRIMARY KEY (dmuapp_id);


--
-- Name: adm_mst_user_application_temp dge_mst_user_application_temp_dmuat_username_key; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_application_temp
    ADD CONSTRAINT dge_mst_user_application_temp_dmuat_username_key UNIQUE (dmuat_username);


--
-- Name: adm_mst_user_application_temp dge_mst_user_application_temp_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_application_temp
    ADD CONSTRAINT dge_mst_user_application_temp_pk PRIMARY KEY (dmuat_id);


--
-- Name: adm_mst_user_menu dge_mst_user_menu_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_menu
    ADD CONSTRAINT dge_mst_user_menu_pk PRIMARY KEY (dmum_id);


--
-- Name: adm_mst_user_menu_temp dge_mst_user_menu_temp_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_menu_temp
    ADD CONSTRAINT dge_mst_user_menu_temp_pk PRIMARY KEY (dmumt_id);


--
-- Name: adm_sec_modules dge_sec_modules_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_sec_modules
    ADD CONSTRAINT dge_sec_modules_pk PRIMARY KEY (dsmd_module_id);


--
-- Name: dge_mst_menu_inherit pk_dge_mst_menu_inherit; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.dge_mst_menu_inherit
    ADD CONSTRAINT pk_dge_mst_menu_inherit PRIMARY KEY (dmmi_menu_parent_id, dmmi_menu_child_id);


--
-- Name: dge_mst_user_application_device pk_dge_mst_user_application_device; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.dge_mst_user_application_device
    ADD CONSTRAINT pk_dge_mst_user_application_device PRIMARY KEY (dmuad_device_id, dmuad_user_id);


--
-- Name: adm_mst_company_application uq_company_application; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_company_application
    ADD CONSTRAINT uq_company_application UNIQUE (dmca_company_id, dmca_application_id);


--
-- Name: adm_mst_company_module uq_company_module; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_company_module
    ADD CONSTRAINT uq_company_module UNIQUE (dmcm_company_id, dmcm_module_id);


--
-- Name: adm_sec_user_pass_recov utl_appl_log_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_sec_user_pass_recov
    ADD CONSTRAINT utl_appl_log_pk PRIMARY KEY (dsup_id);


--
-- Name: utl_sys_config utl_sys_config_pk; Type: CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.utl_sys_config
    ADD CONSTRAINT utl_sys_config_pk PRIMARY KEY (usc_appl, usc_key);


--
-- Name: crm_activity crm_activity_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_activity
    ADD CONSTRAINT crm_activity_pkey PRIMARY KEY (activity_id);


--
-- Name: crm_activity_type crm_activity_type_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_activity_type
    ADD CONSTRAINT crm_activity_type_pkey PRIMARY KEY (activity_type_id);


--
-- Name: crm_competitor crm_competitor_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_competitor
    ADD CONSTRAINT crm_competitor_pkey PRIMARY KEY (competitor_id);


--
-- Name: crm_interaction_log crm_interaction_log_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_interaction_log
    ADD CONSTRAINT crm_interaction_log_pkey PRIMARY KEY (log_id);


--
-- Name: crm_lead_history crm_lead_history_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead_history
    ADD CONSTRAINT crm_lead_history_pkey PRIMARY KEY (history_id);


--
-- Name: crm_lead crm_lead_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead
    ADD CONSTRAINT crm_lead_pkey PRIMARY KEY (lead_id);


--
-- Name: crm_lead_source crm_lead_source_name_key; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead_source
    ADD CONSTRAINT crm_lead_source_name_key UNIQUE (name);


--
-- Name: crm_lead_source crm_lead_source_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead_source
    ADD CONSTRAINT crm_lead_source_pkey PRIMARY KEY (lead_source_id);


--
-- Name: crm_lost_reason crm_lost_reason_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lost_reason
    ADD CONSTRAINT crm_lost_reason_pkey PRIMARY KEY (lost_reason_id);


--
-- Name: crm_monthly_target crm_monthly_target_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_monthly_target
    ADD CONSTRAINT crm_monthly_target_pkey PRIMARY KEY (target_id);


--
-- Name: crm_stage crm_stage_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_stage
    ADD CONSTRAINT crm_stage_pkey PRIMARY KEY (stage_id);


--
-- Name: crm_ticket_conversations crm_ticket_conversations_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_ticket_conversations
    ADD CONSTRAINT crm_ticket_conversations_pkey PRIMARY KEY (conversation_id);


--
-- Name: crm_tickets crm_tickets_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_tickets
    ADD CONSTRAINT crm_tickets_pkey PRIMARY KEY (ticket_id);


--
-- Name: crm_tickets crm_tickets_ticket_number_key; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_tickets
    ADD CONSTRAINT crm_tickets_ticket_number_key UNIQUE (ticket_number);


--
-- Name: hr_employee hr_employee_email_key; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.hr_employee
    ADD CONSTRAINT hr_employee_email_key UNIQUE (email);


--
-- Name: hr_employee hr_employee_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.hr_employee
    ADD CONSTRAINT hr_employee_pkey PRIMARY KEY (employee_id);


--
-- Name: hr_job hr_job_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.hr_job
    ADD CONSTRAINT hr_job_pkey PRIMARY KEY (job_id);


--
-- Name: ir_attachment ir_attachment_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.ir_attachment
    ADD CONSTRAINT ir_attachment_pkey PRIMARY KEY (attachment_id);


--
-- Name: lead_competitor_rel lead_competitor_rel_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.lead_competitor_rel
    ADD CONSTRAINT lead_competitor_rel_pkey PRIMARY KEY (lead_id, competitor_id);


--
-- Name: mail_message mail_message_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.mail_message
    ADD CONSTRAINT mail_message_pkey PRIMARY KEY (message_id);


--
-- Name: res_currency res_currency_name_key; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_currency
    ADD CONSTRAINT res_currency_name_key UNIQUE (name);


--
-- Name: res_currency res_currency_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_currency
    ADD CONSTRAINT res_currency_pkey PRIMARY KEY (currency_id);


--
-- Name: res_partner_category res_partner_category_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_partner_category
    ADD CONSTRAINT res_partner_category_pkey PRIMARY KEY (category_id);


--
-- Name: res_partner_contact res_partner_contact_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_partner_contact
    ADD CONSTRAINT res_partner_contact_pkey PRIMARY KEY (contact_id);


--
-- Name: res_partner res_partner_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_partner
    ADD CONSTRAINT res_partner_pkey PRIMARY KEY (partner_id);


--
-- Name: res_users res_users_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_users
    ADD CONSTRAINT res_users_pkey PRIMARY KEY (user_id);


--
-- Name: res_users res_users_username_key; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_users
    ADD CONSTRAINT res_users_username_key UNIQUE (username);


--
-- Name: sales_targets sales_targets_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.sales_targets
    ADD CONSTRAINT sales_targets_pkey PRIMARY KEY (target_id);


--
-- Name: sales_team sales_team_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.sales_team
    ADD CONSTRAINT sales_team_pkey PRIMARY KEY (team_id);


--
-- Name: utm_campaign utm_campaign_name_key; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.utm_campaign
    ADD CONSTRAINT utm_campaign_name_key UNIQUE (name);


--
-- Name: utm_campaign utm_campaign_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.utm_campaign
    ADD CONSTRAINT utm_campaign_pkey PRIMARY KEY (campaign_id);


--
-- Name: utm_medium utm_medium_name_key; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.utm_medium
    ADD CONSTRAINT utm_medium_name_key UNIQUE (name);


--
-- Name: utm_medium utm_medium_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.utm_medium
    ADD CONSTRAINT utm_medium_pkey PRIMARY KEY (medium_id);


--
-- Name: utm_source utm_source_name_key; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.utm_source
    ADD CONSTRAINT utm_source_name_key UNIQUE (name);


--
-- Name: utm_source utm_source_pkey; Type: CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.utm_source
    ADD CONSTRAINT utm_source_pkey PRIMARY KEY (source_id);


--
-- Name: hr_log_salary_change hr_log_salary_change_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_log_salary_change
    ADD CONSTRAINT hr_log_salary_change_pkey PRIMARY KEY (dlog_id);


--
-- Name: hr_mst_approval_flow hr_mst_approval_flow_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_approval_flow
    ADD CONSTRAINT hr_mst_approval_flow_pkey PRIMARY KEY (daflow_id);


--
-- Name: hr_mst_attendance_rule hr_mst_attendance_rule_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_attendance_rule
    ADD CONSTRAINT hr_mst_attendance_rule_pkey PRIMARY KEY (datt_rule_id);


--
-- Name: hr_mst_bpjs_setting hr_mst_bpjs_setting_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_bpjs_setting
    ADD CONSTRAINT hr_mst_bpjs_setting_pkey PRIMARY KEY (dbpjs_id);


--
-- Name: hr_mst_company_config hr_mst_company_config_dcomp_code_key; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_company_config
    ADD CONSTRAINT hr_mst_company_config_dcomp_code_key UNIQUE (dcomp_code);


--
-- Name: hr_mst_company_config hr_mst_company_config_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_company_config
    ADD CONSTRAINT hr_mst_company_config_pkey PRIMARY KEY (dcomp_id);


--
-- Name: hr_mst_company_setting hr_mst_company_setting_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_company_setting
    ADD CONSTRAINT hr_mst_company_setting_pkey PRIMARY KEY (dset_code);


--
-- Name: hr_mst_department hr_mst_department_code_uk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_department
    ADD CONSTRAINT hr_mst_department_code_uk UNIQUE (dmdep_code);


--
-- Name: hr_mst_department hr_mst_department_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_department
    ADD CONSTRAINT hr_mst_department_pk PRIMARY KEY (dmdep_id);


--
-- Name: hr_mst_employee hr_mst_employee_code_uk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee
    ADD CONSTRAINT hr_mst_employee_code_uk UNIQUE (dmemp_employee_code);


--
-- Name: hr_mst_employee hr_mst_employee_nik_uk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee
    ADD CONSTRAINT hr_mst_employee_nik_uk UNIQUE (dmemp_nik);


--
-- Name: hr_mst_employee_payroll_config hr_mst_employee_payroll_config_depc_employee_code_key; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee_payroll_config
    ADD CONSTRAINT hr_mst_employee_payroll_config_depc_employee_code_key UNIQUE (depc_employee_code);


--
-- Name: hr_mst_employee_payroll_config hr_mst_employee_payroll_config_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee_payroll_config
    ADD CONSTRAINT hr_mst_employee_payroll_config_pkey PRIMARY KEY (depc_id);


--
-- Name: hr_mst_employee hr_mst_employee_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee
    ADD CONSTRAINT hr_mst_employee_pk PRIMARY KEY (dmemp_id);


--
-- Name: hr_mst_employee_tax hr_mst_employee_tax_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee_tax
    ADD CONSTRAINT hr_mst_employee_tax_pkey PRIMARY KEY (detax_id);


--
-- Name: hr_mst_formula hr_mst_formula_dform_code_key; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_formula
    ADD CONSTRAINT hr_mst_formula_dform_code_key UNIQUE (dform_code);


--
-- Name: hr_mst_formula hr_mst_formula_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_formula
    ADD CONSTRAINT hr_mst_formula_pkey PRIMARY KEY (dform_id);


--
-- Name: hr_mst_holiday hr_mst_holiday_date_uk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_holiday
    ADD CONSTRAINT hr_mst_holiday_date_uk UNIQUE (dmhol_date);


--
-- Name: hr_mst_holiday hr_mst_holiday_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_holiday
    ADD CONSTRAINT hr_mst_holiday_pk PRIMARY KEY (dmhol_id);


--
-- Name: hr_mst_job_grade hr_mst_job_grade_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_job_grade
    ADD CONSTRAINT hr_mst_job_grade_pkey PRIMARY KEY (dgrade_id);


--
-- Name: hr_mst_leave_type hr_mst_leave_type_code_uk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_leave_type
    ADD CONSTRAINT hr_mst_leave_type_code_uk UNIQUE (dmlty_code);


--
-- Name: hr_mst_leave_type hr_mst_leave_type_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_leave_type
    ADD CONSTRAINT hr_mst_leave_type_pk PRIMARY KEY (dmlty_id);


--
-- Name: hr_mst_loan_type hr_mst_loan_type_dloant_code_key; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_loan_type
    ADD CONSTRAINT hr_mst_loan_type_dloant_code_key UNIQUE (dloant_code);


--
-- Name: hr_mst_loan_type hr_mst_loan_type_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_loan_type
    ADD CONSTRAINT hr_mst_loan_type_pkey PRIMARY KEY (dloant_id);


--
-- Name: hr_mst_payroll_period hr_mst_payroll_period_dper_code_key; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_payroll_period
    ADD CONSTRAINT hr_mst_payroll_period_dper_code_key UNIQUE (dper_code);


--
-- Name: hr_mst_payroll_period hr_mst_payroll_period_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_payroll_period
    ADD CONSTRAINT hr_mst_payroll_period_pkey PRIMARY KEY (dper_id);


--
-- Name: hr_mst_payroll_rule hr_mst_payroll_rule_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_payroll_rule
    ADD CONSTRAINT hr_mst_payroll_rule_pkey PRIMARY KEY (drule_id);


--
-- Name: hr_mst_position hr_mst_position_code_uk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_position
    ADD CONSTRAINT hr_mst_position_code_uk UNIQUE (dmpos_code);


--
-- Name: hr_mst_position hr_mst_position_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_position
    ADD CONSTRAINT hr_mst_position_pk PRIMARY KEY (dmpos_id);


--
-- Name: hr_mst_ptkp hr_mst_ptkp_dptkp_code_key; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_ptkp
    ADD CONSTRAINT hr_mst_ptkp_dptkp_code_key UNIQUE (dptkp_code);


--
-- Name: hr_mst_ptkp hr_mst_ptkp_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_ptkp
    ADD CONSTRAINT hr_mst_ptkp_pkey PRIMARY KEY (dptkp_id);


--
-- Name: hr_mst_salary_component hr_mst_salary_component_code_uk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_salary_component
    ADD CONSTRAINT hr_mst_salary_component_code_uk UNIQUE (dmsc_code);


--
-- Name: hr_mst_salary_component hr_mst_salary_component_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_salary_component
    ADD CONSTRAINT hr_mst_salary_component_pk PRIMARY KEY (dmsc_id);


--
-- Name: hr_mst_shift hr_mst_shift_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_shift
    ADD CONSTRAINT hr_mst_shift_pkey PRIMARY KEY (dshift_id);


--
-- Name: hr_mst_tax_rate hr_mst_tax_rate_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_tax_rate
    ADD CONSTRAINT hr_mst_tax_rate_pkey PRIMARY KEY (dtax_id);


--
-- Name: hr_txn_approval hr_txn_approval_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_approval
    ADD CONSTRAINT hr_txn_approval_pkey PRIMARY KEY (dapp_id);


--
-- Name: hr_txn_attendance hr_txn_attendance_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_attendance
    ADD CONSTRAINT hr_txn_attendance_pk PRIMARY KEY (dmatn_id);


--
-- Name: hr_txn_career_history hr_txn_career_history_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_career_history
    ADD CONSTRAINT hr_txn_career_history_pk PRIMARY KEY (dmcar_id);


--
-- Name: hr_txn_contract hr_txn_contract_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_contract
    ADD CONSTRAINT hr_txn_contract_pk PRIMARY KEY (dmcon_id);


--
-- Name: hr_txn_document hr_txn_document_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_document
    ADD CONSTRAINT hr_txn_document_pk PRIMARY KEY (dmdoc_id);


--
-- Name: hr_txn_employee_payroll_rule hr_txn_employee_payroll_rule_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_payroll_rule
    ADD CONSTRAINT hr_txn_employee_payroll_rule_pkey PRIMARY KEY (depr_id);


--
-- Name: hr_txn_employee_salary_detail hr_txn_employee_salary_detail_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_salary_detail
    ADD CONSTRAINT hr_txn_employee_salary_detail_pk PRIMARY KEY (dmsald_id);


--
-- Name: hr_txn_employee_salary_detail hr_txn_employee_salary_detail_uk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_salary_detail
    ADD CONSTRAINT hr_txn_employee_salary_detail_uk UNIQUE (dmsald_salary_id, dmsald_component_id);


--
-- Name: hr_txn_employee_salary hr_txn_employee_salary_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_salary
    ADD CONSTRAINT hr_txn_employee_salary_pk PRIMARY KEY (dmsal_id);


--
-- Name: hr_txn_employee_shift hr_txn_employee_shift_pkey; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_shift
    ADD CONSTRAINT hr_txn_employee_shift_pkey PRIMARY KEY (deshift_id);


--
-- Name: hr_txn_leave_balance hr_txn_leave_balance_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_leave_balance
    ADD CONSTRAINT hr_txn_leave_balance_pk PRIMARY KEY (dmlbal_id);


--
-- Name: hr_txn_leave_request hr_txn_leave_request_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_leave_request
    ADD CONSTRAINT hr_txn_leave_request_pk PRIMARY KEY (dmlreq_id);


--
-- Name: hr_txn_loan hr_txn_loan_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_loan
    ADD CONSTRAINT hr_txn_loan_pk PRIMARY KEY (dmlon_id);


--
-- Name: hr_txn_overtime hr_txn_overtime_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_overtime
    ADD CONSTRAINT hr_txn_overtime_pk PRIMARY KEY (dmovt_id);


--
-- Name: hr_txn_payslip_line hr_txn_payslip_line_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_payslip_line
    ADD CONSTRAINT hr_txn_payslip_line_pk PRIMARY KEY (dmpsl_id);


--
-- Name: hr_txn_payslip hr_txn_payslip_pk; Type: CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_payslip
    ADD CONSTRAINT hr_txn_payslip_pk PRIMARY KEY (dmps_id);


--
-- Name: org_domain ORG_DOMAIN_pkey; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.org_domain
    ADD CONSTRAINT "ORG_DOMAIN_pkey" PRIMARY KEY (id, name);


--
-- Name: org ORG_pkey; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.org
    ADD CONSTRAINT "ORG_pkey" PRIMARY KEY (id);


--
-- Name: server_config SERVER_CONFIG_pkey; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.server_config
    ADD CONSTRAINT "SERVER_CONFIG_pkey" PRIMARY KEY (server_config_key);


--
-- Name: keycloak_role UK_J3RWUVD56ONTGSUHOGM184WW2-2; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.keycloak_role
    ADD CONSTRAINT "UK_J3RWUVD56ONTGSUHOGM184WW2-2" UNIQUE (name, client_realm_constraint);


--
-- Name: client_auth_flow_bindings c_cli_flow_bind; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_auth_flow_bindings
    ADD CONSTRAINT c_cli_flow_bind PRIMARY KEY (client_id, binding_name);


--
-- Name: client_scope_client c_cli_scope_bind; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_scope_client
    ADD CONSTRAINT c_cli_scope_bind PRIMARY KEY (client_id, scope_id);


--
-- Name: client_initial_access cnstr_client_init_acc_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_initial_access
    ADD CONSTRAINT cnstr_client_init_acc_pk PRIMARY KEY (id);


--
-- Name: realm_default_groups con_group_id_def_groups; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_default_groups
    ADD CONSTRAINT con_group_id_def_groups UNIQUE (group_id);


--
-- Name: broker_link constr_broker_link_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.broker_link
    ADD CONSTRAINT constr_broker_link_pk PRIMARY KEY (identity_provider, user_id);


--
-- Name: component_config constr_component_config_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.component_config
    ADD CONSTRAINT constr_component_config_pk PRIMARY KEY (id);


--
-- Name: component constr_component_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.component
    ADD CONSTRAINT constr_component_pk PRIMARY KEY (id);


--
-- Name: fed_user_required_action constr_fed_required_action; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.fed_user_required_action
    ADD CONSTRAINT constr_fed_required_action PRIMARY KEY (required_action, user_id);


--
-- Name: fed_user_attribute constr_fed_user_attr_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.fed_user_attribute
    ADD CONSTRAINT constr_fed_user_attr_pk PRIMARY KEY (id);


--
-- Name: fed_user_consent constr_fed_user_consent_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.fed_user_consent
    ADD CONSTRAINT constr_fed_user_consent_pk PRIMARY KEY (id);


--
-- Name: fed_user_credential constr_fed_user_cred_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.fed_user_credential
    ADD CONSTRAINT constr_fed_user_cred_pk PRIMARY KEY (id);


--
-- Name: fed_user_group_membership constr_fed_user_group; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.fed_user_group_membership
    ADD CONSTRAINT constr_fed_user_group PRIMARY KEY (group_id, user_id);


--
-- Name: fed_user_role_mapping constr_fed_user_role; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.fed_user_role_mapping
    ADD CONSTRAINT constr_fed_user_role PRIMARY KEY (role_id, user_id);


--
-- Name: federated_user constr_federated_user; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.federated_user
    ADD CONSTRAINT constr_federated_user PRIMARY KEY (id);


--
-- Name: realm_default_groups constr_realm_default_groups; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_default_groups
    ADD CONSTRAINT constr_realm_default_groups PRIMARY KEY (realm_id, group_id);


--
-- Name: realm_enabled_event_types constr_realm_enabl_event_types; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_enabled_event_types
    ADD CONSTRAINT constr_realm_enabl_event_types PRIMARY KEY (realm_id, value);


--
-- Name: realm_events_listeners constr_realm_events_listeners; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_events_listeners
    ADD CONSTRAINT constr_realm_events_listeners PRIMARY KEY (realm_id, value);


--
-- Name: realm_supported_locales constr_realm_supported_locales; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_supported_locales
    ADD CONSTRAINT constr_realm_supported_locales PRIMARY KEY (realm_id, value);


--
-- Name: identity_provider constraint_2b; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.identity_provider
    ADD CONSTRAINT constraint_2b PRIMARY KEY (internal_id);


--
-- Name: client_attributes constraint_3c; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_attributes
    ADD CONSTRAINT constraint_3c PRIMARY KEY (client_id, name);


--
-- Name: event_entity constraint_4; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.event_entity
    ADD CONSTRAINT constraint_4 PRIMARY KEY (id);


--
-- Name: federated_identity constraint_40; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.federated_identity
    ADD CONSTRAINT constraint_40 PRIMARY KEY (identity_provider, user_id);


--
-- Name: realm constraint_4a; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm
    ADD CONSTRAINT constraint_4a PRIMARY KEY (id);


--
-- Name: user_federation_provider constraint_5c; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_federation_provider
    ADD CONSTRAINT constraint_5c PRIMARY KEY (id);


--
-- Name: client constraint_7; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client
    ADD CONSTRAINT constraint_7 PRIMARY KEY (id);


--
-- Name: scope_mapping constraint_81; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.scope_mapping
    ADD CONSTRAINT constraint_81 PRIMARY KEY (client_id, role_id);


--
-- Name: client_node_registrations constraint_84; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_node_registrations
    ADD CONSTRAINT constraint_84 PRIMARY KEY (client_id, name);


--
-- Name: realm_attribute constraint_9; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_attribute
    ADD CONSTRAINT constraint_9 PRIMARY KEY (name, realm_id);


--
-- Name: realm_required_credential constraint_92; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_required_credential
    ADD CONSTRAINT constraint_92 PRIMARY KEY (realm_id, type);


--
-- Name: keycloak_role constraint_a; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.keycloak_role
    ADD CONSTRAINT constraint_a PRIMARY KEY (id);


--
-- Name: admin_event_entity constraint_admin_event_entity; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.admin_event_entity
    ADD CONSTRAINT constraint_admin_event_entity PRIMARY KEY (id);


--
-- Name: authenticator_config_entry constraint_auth_cfg_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.authenticator_config_entry
    ADD CONSTRAINT constraint_auth_cfg_pk PRIMARY KEY (authenticator_id, name);


--
-- Name: authentication_execution constraint_auth_exec_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.authentication_execution
    ADD CONSTRAINT constraint_auth_exec_pk PRIMARY KEY (id);


--
-- Name: authentication_flow constraint_auth_flow_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.authentication_flow
    ADD CONSTRAINT constraint_auth_flow_pk PRIMARY KEY (id);


--
-- Name: authenticator_config constraint_auth_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.authenticator_config
    ADD CONSTRAINT constraint_auth_pk PRIMARY KEY (id);


--
-- Name: user_role_mapping constraint_c; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_role_mapping
    ADD CONSTRAINT constraint_c PRIMARY KEY (role_id, user_id);


--
-- Name: composite_role constraint_composite_role; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.composite_role
    ADD CONSTRAINT constraint_composite_role PRIMARY KEY (composite, child_role);


--
-- Name: identity_provider_config constraint_d; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.identity_provider_config
    ADD CONSTRAINT constraint_d PRIMARY KEY (identity_provider_id, name);


--
-- Name: policy_config constraint_dpc; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.policy_config
    ADD CONSTRAINT constraint_dpc PRIMARY KEY (policy_id, name);


--
-- Name: realm_smtp_config constraint_e; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_smtp_config
    ADD CONSTRAINT constraint_e PRIMARY KEY (realm_id, name);


--
-- Name: credential constraint_f; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.credential
    ADD CONSTRAINT constraint_f PRIMARY KEY (id);


--
-- Name: user_federation_config constraint_f9; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_federation_config
    ADD CONSTRAINT constraint_f9 PRIMARY KEY (user_federation_provider_id, name);


--
-- Name: resource_server_perm_ticket constraint_fapmt; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_perm_ticket
    ADD CONSTRAINT constraint_fapmt PRIMARY KEY (id);


--
-- Name: resource_server_resource constraint_farsr; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_resource
    ADD CONSTRAINT constraint_farsr PRIMARY KEY (id);


--
-- Name: resource_server_policy constraint_farsrp; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_policy
    ADD CONSTRAINT constraint_farsrp PRIMARY KEY (id);


--
-- Name: associated_policy constraint_farsrpap; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.associated_policy
    ADD CONSTRAINT constraint_farsrpap PRIMARY KEY (policy_id, associated_policy_id);


--
-- Name: resource_policy constraint_farsrpp; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_policy
    ADD CONSTRAINT constraint_farsrpp PRIMARY KEY (resource_id, policy_id);


--
-- Name: resource_server_scope constraint_farsrs; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_scope
    ADD CONSTRAINT constraint_farsrs PRIMARY KEY (id);


--
-- Name: resource_scope constraint_farsrsp; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_scope
    ADD CONSTRAINT constraint_farsrsp PRIMARY KEY (resource_id, scope_id);


--
-- Name: scope_policy constraint_farsrsps; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.scope_policy
    ADD CONSTRAINT constraint_farsrsps PRIMARY KEY (scope_id, policy_id);


--
-- Name: user_entity constraint_fb; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_entity
    ADD CONSTRAINT constraint_fb PRIMARY KEY (id);


--
-- Name: user_federation_mapper_config constraint_fedmapper_cfg_pm; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_federation_mapper_config
    ADD CONSTRAINT constraint_fedmapper_cfg_pm PRIMARY KEY (user_federation_mapper_id, name);


--
-- Name: user_federation_mapper constraint_fedmapperpm; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_federation_mapper
    ADD CONSTRAINT constraint_fedmapperpm PRIMARY KEY (id);


--
-- Name: fed_user_consent_cl_scope constraint_fgrntcsnt_clsc_pm; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.fed_user_consent_cl_scope
    ADD CONSTRAINT constraint_fgrntcsnt_clsc_pm PRIMARY KEY (user_consent_id, scope_id, parameter);


--
-- Name: user_consent_client_scope constraint_grntcsnt_clsc_pm; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_consent_client_scope
    ADD CONSTRAINT constraint_grntcsnt_clsc_pm PRIMARY KEY (user_consent_id, scope_id, parameter);


--
-- Name: user_consent constraint_grntcsnt_pm; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_consent
    ADD CONSTRAINT constraint_grntcsnt_pm PRIMARY KEY (id);


--
-- Name: keycloak_group constraint_group; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.keycloak_group
    ADD CONSTRAINT constraint_group PRIMARY KEY (id);


--
-- Name: group_attribute constraint_group_attribute_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.group_attribute
    ADD CONSTRAINT constraint_group_attribute_pk PRIMARY KEY (id);


--
-- Name: group_role_mapping constraint_group_role; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.group_role_mapping
    ADD CONSTRAINT constraint_group_role PRIMARY KEY (role_id, group_id);


--
-- Name: identity_provider_mapper constraint_idpm; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.identity_provider_mapper
    ADD CONSTRAINT constraint_idpm PRIMARY KEY (id);


--
-- Name: idp_mapper_config constraint_idpmconfig; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.idp_mapper_config
    ADD CONSTRAINT constraint_idpmconfig PRIMARY KEY (idp_mapper_id, name);


--
-- Name: jgroups_ping constraint_jgroups_ping; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.jgroups_ping
    ADD CONSTRAINT constraint_jgroups_ping PRIMARY KEY (address);


--
-- Name: migration_model constraint_migmod; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.migration_model
    ADD CONSTRAINT constraint_migmod PRIMARY KEY (id);


--
-- Name: offline_client_session constraint_offl_cl_ses_pk3; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.offline_client_session
    ADD CONSTRAINT constraint_offl_cl_ses_pk3 PRIMARY KEY (user_session_id, client_id, client_storage_provider, external_client_id, offline_flag);


--
-- Name: offline_user_session constraint_offl_us_ses_pk2; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.offline_user_session
    ADD CONSTRAINT constraint_offl_us_ses_pk2 PRIMARY KEY (user_session_id, offline_flag);


--
-- Name: org_invitation constraint_org_invitation; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.org_invitation
    ADD CONSTRAINT constraint_org_invitation PRIMARY KEY (id);


--
-- Name: protocol_mapper constraint_pcm; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.protocol_mapper
    ADD CONSTRAINT constraint_pcm PRIMARY KEY (id);


--
-- Name: protocol_mapper_config constraint_pmconfig; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.protocol_mapper_config
    ADD CONSTRAINT constraint_pmconfig PRIMARY KEY (protocol_mapper_id, name);


--
-- Name: redirect_uris constraint_redirect_uris; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.redirect_uris
    ADD CONSTRAINT constraint_redirect_uris PRIMARY KEY (client_id, value);


--
-- Name: required_action_config constraint_req_act_cfg_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.required_action_config
    ADD CONSTRAINT constraint_req_act_cfg_pk PRIMARY KEY (required_action_id, name);


--
-- Name: required_action_provider constraint_req_act_prv_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.required_action_provider
    ADD CONSTRAINT constraint_req_act_prv_pk PRIMARY KEY (id);


--
-- Name: user_required_action constraint_required_action; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_required_action
    ADD CONSTRAINT constraint_required_action PRIMARY KEY (required_action, user_id);


--
-- Name: resource_uris constraint_resour_uris_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_uris
    ADD CONSTRAINT constraint_resour_uris_pk PRIMARY KEY (resource_id, value);


--
-- Name: role_attribute constraint_role_attribute_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.role_attribute
    ADD CONSTRAINT constraint_role_attribute_pk PRIMARY KEY (id);


--
-- Name: revoked_token constraint_rt; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.revoked_token
    ADD CONSTRAINT constraint_rt PRIMARY KEY (id);


--
-- Name: user_attribute constraint_user_attribute_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_attribute
    ADD CONSTRAINT constraint_user_attribute_pk PRIMARY KEY (id);


--
-- Name: user_group_membership constraint_user_group; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_group_membership
    ADD CONSTRAINT constraint_user_group PRIMARY KEY (group_id, user_id);


--
-- Name: user_ver_credential constraint_vcred_pm; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_ver_credential
    ADD CONSTRAINT constraint_vcred_pm PRIMARY KEY (id);


--
-- Name: web_origins constraint_web_origins; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.web_origins
    ADD CONSTRAINT constraint_web_origins PRIMARY KEY (client_id, value);


--
-- Name: databasechangeloglock databasechangeloglock_pkey; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.databasechangeloglock
    ADD CONSTRAINT databasechangeloglock_pkey PRIMARY KEY (id);


--
-- Name: auth_session pk_auth_session; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.auth_session
    ADD CONSTRAINT pk_auth_session PRIMARY KEY (root_auth_session_id, tab_id);


--
-- Name: client_scope_attributes pk_cl_tmpl_attr; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_scope_attributes
    ADD CONSTRAINT pk_cl_tmpl_attr PRIMARY KEY (scope_id, name);


--
-- Name: client_scope pk_cli_template; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_scope
    ADD CONSTRAINT pk_cli_template PRIMARY KEY (id);


--
-- Name: cluster_event pk_cluster_event; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.cluster_event
    ADD CONSTRAINT pk_cluster_event PRIMARY KEY (id, target_cluster);


--
-- Name: fed_issued_ver_credential pk_fed_issued_ver_credential; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.fed_issued_ver_credential
    ADD CONSTRAINT pk_fed_issued_ver_credential PRIMARY KEY (id);


--
-- Name: fed_user_ver_credential pk_fed_user_ver_credential; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.fed_user_ver_credential
    ADD CONSTRAINT pk_fed_user_ver_credential PRIMARY KEY (id);


--
-- Name: issued_ver_credential pk_issued_ver_credential; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.issued_ver_credential
    ADD CONSTRAINT pk_issued_ver_credential PRIMARY KEY (id);


--
-- Name: login_failure pk_login_failure; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.login_failure
    ADD CONSTRAINT pk_login_failure PRIMARY KEY (realm_id, user_id);


--
-- Name: outbox_entry pk_outbox_entry; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.outbox_entry
    ADD CONSTRAINT pk_outbox_entry PRIMARY KEY (id);


--
-- Name: resource_server pk_resource_server; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server
    ADD CONSTRAINT pk_resource_server PRIMARY KEY (id);


--
-- Name: root_auth_session pk_root_auth_session; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.root_auth_session
    ADD CONSTRAINT pk_root_auth_session PRIMARY KEY (id);


--
-- Name: single_use_object pk_single_use_object; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.single_use_object
    ADD CONSTRAINT pk_single_use_object PRIMARY KEY (id);


--
-- Name: client_scope_role_mapping pk_template_scope; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_scope_role_mapping
    ADD CONSTRAINT pk_template_scope PRIMARY KEY (scope_id, role_id);


--
-- Name: workflow_state pk_workflow_state; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.workflow_state
    ADD CONSTRAINT pk_workflow_state PRIMARY KEY (execution_id);


--
-- Name: default_client_scope r_def_cli_scope_bind; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.default_client_scope
    ADD CONSTRAINT r_def_cli_scope_bind PRIMARY KEY (realm_id, scope_id);


--
-- Name: realm_localizations realm_localizations_pkey; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_localizations
    ADD CONSTRAINT realm_localizations_pkey PRIMARY KEY (realm_id, locale);


--
-- Name: resource_attribute res_attr_pk; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_attribute
    ADD CONSTRAINT res_attr_pk PRIMARY KEY (id);


--
-- Name: keycloak_group sibling_names; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.keycloak_group
    ADD CONSTRAINT sibling_names UNIQUE (realm_id, parent_group, name);


--
-- Name: outbox_entry uc_outbox_kind_owner_correlation; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.outbox_entry
    ADD CONSTRAINT uc_outbox_kind_owner_correlation UNIQUE (entry_kind, owner_id, correlation_id);


--
-- Name: identity_provider uk_2daelwnibji49avxsrtuf6xj33; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.identity_provider
    ADD CONSTRAINT uk_2daelwnibji49avxsrtuf6xj33 UNIQUE (provider_alias, realm_id);


--
-- Name: client uk_b71cjlbenv945rb6gcon438at; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client
    ADD CONSTRAINT uk_b71cjlbenv945rb6gcon438at UNIQUE (realm_id, client_id);


--
-- Name: client_scope uk_cli_scope; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_scope
    ADD CONSTRAINT uk_cli_scope UNIQUE (realm_id, name);


--
-- Name: user_entity uk_dykn684sl8up1crfei6eckhd7; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_entity
    ADD CONSTRAINT uk_dykn684sl8up1crfei6eckhd7 UNIQUE (realm_id, email_constraint);


--
-- Name: user_consent uk_external_consent; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_consent
    ADD CONSTRAINT uk_external_consent UNIQUE (client_storage_provider, external_client_id, user_id);


--
-- Name: fed_user_ver_credential uk_fed_user_vc; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.fed_user_ver_credential
    ADD CONSTRAINT uk_fed_user_vc UNIQUE (user_id, client_scope_id);


--
-- Name: resource_server_resource uk_frsr6t700s9v50bu18ws5ha6; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_resource
    ADD CONSTRAINT uk_frsr6t700s9v50bu18ws5ha6 UNIQUE (name, owner, resource_server_id);


--
-- Name: resource_server_perm_ticket uk_frsr6t700s9v50bu18ws5pmt; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_perm_ticket
    ADD CONSTRAINT uk_frsr6t700s9v50bu18ws5pmt UNIQUE (owner, requester, resource_server_id, resource_id, scope_id);


--
-- Name: resource_server_policy uk_frsrpt700s9v50bu18ws5ha6; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_policy
    ADD CONSTRAINT uk_frsrpt700s9v50bu18ws5ha6 UNIQUE (name, resource_server_id);


--
-- Name: resource_server_scope uk_frsrst700s9v50bu18ws5ha6; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_scope
    ADD CONSTRAINT uk_frsrst700s9v50bu18ws5ha6 UNIQUE (name, resource_server_id);


--
-- Name: user_ver_credential uk_kkuwuvd67ontgsugogm8uewre; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_ver_credential
    ADD CONSTRAINT uk_kkuwuvd67ontgsugogm8uewre UNIQUE (user_id, client_scope_id);


--
-- Name: user_consent uk_local_consent; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_consent
    ADD CONSTRAINT uk_local_consent UNIQUE (client_id, user_id);


--
-- Name: migration_model uk_migration_update_time; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.migration_model
    ADD CONSTRAINT uk_migration_update_time UNIQUE (update_time);


--
-- Name: migration_model uk_migration_version; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.migration_model
    ADD CONSTRAINT uk_migration_version UNIQUE (version);


--
-- Name: org uk_org_alias; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.org
    ADD CONSTRAINT uk_org_alias UNIQUE (realm_id, alias);


--
-- Name: org uk_org_group; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.org
    ADD CONSTRAINT uk_org_group UNIQUE (group_id);


--
-- Name: org_invitation uk_org_invitation_email; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.org_invitation
    ADD CONSTRAINT uk_org_invitation_email UNIQUE (organization_id, email);


--
-- Name: org uk_org_name; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.org
    ADD CONSTRAINT uk_org_name UNIQUE (realm_id, name);


--
-- Name: realm uk_orvsdmla56612eaefiq6wl5oi; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm
    ADD CONSTRAINT uk_orvsdmla56612eaefiq6wl5oi UNIQUE (name);


--
-- Name: user_entity uk_ru8tt6t700s9v50bu18ws5ha6; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_entity
    ADD CONSTRAINT uk_ru8tt6t700s9v50bu18ws5ha6 UNIQUE (realm_id, username);


--
-- Name: workflow_state uq_workflow_resource; Type: CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.workflow_state
    ADD CONSTRAINT uq_workflow_resource UNIQUE (workflow_id, resource_id);


--
-- Name: adm_mst_user_menu_idx; Type: INDEX; Schema: schema_admin; Owner: postgres
--

CREATE INDEX adm_mst_user_menu_idx ON schema_admin.adm_mst_user_menu USING btree (dmum_user_id, dmum_valid_from, dmum_valid_to) WHERE (dmum_is_view = (1)::numeric);


--
-- Name: idx_dge_mst_menu_lower_link; Type: INDEX; Schema: schema_admin; Owner: postgres
--

CREATE INDEX idx_dge_mst_menu_lower_link ON schema_admin.adm_mst_menu USING btree (lower((dmmenu_menu_link)::text));


--
-- Name: idx_dsup_token; Type: INDEX; Schema: schema_admin; Owner: postgres
--

CREATE INDEX idx_dsup_token ON schema_admin.adm_sec_user_pass_recov USING btree (dsup_token);


--
-- Name: idx_crm_activity_status; Type: INDEX; Schema: schema_crm; Owner: postgres
--

CREATE INDEX idx_crm_activity_status ON schema_crm.crm_activity USING btree (is_done, lead_id);


--
-- Name: fed_user_attr_long_values; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX fed_user_attr_long_values ON schema_keycloak.fed_user_attribute USING btree (long_value_hash, name);


--
-- Name: fed_user_attr_long_values_lower_case; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX fed_user_attr_long_values_lower_case ON schema_keycloak.fed_user_attribute USING btree (long_value_hash_lower_case, name);


--
-- Name: idx_admin_event_time; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_admin_event_time ON schema_keycloak.admin_event_entity USING btree (realm_id, admin_event_time);


--
-- Name: idx_assoc_pol_assoc_pol_id; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_assoc_pol_assoc_pol_id ON schema_keycloak.associated_policy USING btree (associated_policy_id);


--
-- Name: idx_auth_config_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_auth_config_realm ON schema_keycloak.authenticator_config USING btree (realm_id);


--
-- Name: idx_auth_exec_flow; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_auth_exec_flow ON schema_keycloak.authentication_execution USING btree (flow_id);


--
-- Name: idx_auth_exec_realm_flow; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_auth_exec_realm_flow ON schema_keycloak.authentication_execution USING btree (realm_id, flow_id);


--
-- Name: idx_auth_flow_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_auth_flow_realm ON schema_keycloak.authentication_flow USING btree (realm_id);


--
-- Name: idx_broker_link_identity_provider; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_broker_link_identity_provider ON schema_keycloak.broker_link USING btree (realm_id, identity_provider, broker_user_id);


--
-- Name: idx_broker_link_user_id; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_broker_link_user_id ON schema_keycloak.broker_link USING btree (user_id);


--
-- Name: idx_cl_clscope; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_cl_clscope ON schema_keycloak.client_scope_client USING btree (scope_id);


--
-- Name: idx_client_att_by_name_value; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_client_att_by_name_value ON schema_keycloak.client_attributes USING btree (name, substr(value, 1, 255));


--
-- Name: idx_client_id; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_client_id ON schema_keycloak.client USING btree (client_id);


--
-- Name: idx_client_init_acc_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_client_init_acc_realm ON schema_keycloak.client_initial_access USING btree (realm_id);


--
-- Name: idx_clscope_attrs; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_clscope_attrs ON schema_keycloak.client_scope_attributes USING btree (scope_id);


--
-- Name: idx_clscope_cl; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_clscope_cl ON schema_keycloak.client_scope_client USING btree (client_id);


--
-- Name: idx_clscope_protmap; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_clscope_protmap ON schema_keycloak.protocol_mapper USING btree (client_scope_id);


--
-- Name: idx_clscope_role; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_clscope_role ON schema_keycloak.client_scope_role_mapping USING btree (scope_id);


--
-- Name: idx_cluster_event_target; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_cluster_event_target ON schema_keycloak.cluster_event USING btree (target_cluster, created_at);


--
-- Name: idx_compo_config_compo; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_compo_config_compo ON schema_keycloak.component_config USING btree (component_id);


--
-- Name: idx_component_provider_type; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_component_provider_type ON schema_keycloak.component USING btree (provider_type);


--
-- Name: idx_component_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_component_realm ON schema_keycloak.component USING btree (realm_id);


--
-- Name: idx_composite; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_composite ON schema_keycloak.composite_role USING btree (composite);


--
-- Name: idx_composite_child; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_composite_child ON schema_keycloak.composite_role USING btree (child_role);


--
-- Name: idx_defcls_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_defcls_realm ON schema_keycloak.default_client_scope USING btree (realm_id);


--
-- Name: idx_defcls_scope; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_defcls_scope ON schema_keycloak.default_client_scope USING btree (scope_id);


--
-- Name: idx_event_entity_user_id_type; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_event_entity_user_id_type ON schema_keycloak.event_entity USING btree (user_id, type, event_time);


--
-- Name: idx_event_time; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_event_time ON schema_keycloak.event_entity USING btree (realm_id, event_time);


--
-- Name: idx_fed_issued_vc_cred_id; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fed_issued_vc_cred_id ON schema_keycloak.fed_issued_ver_credential USING btree (ver_credential_id);


--
-- Name: idx_fed_issued_vc_expires; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fed_issued_vc_expires ON schema_keycloak.fed_issued_ver_credential USING btree (expires_at);


--
-- Name: idx_fed_issued_vc_storage; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fed_issued_vc_storage ON schema_keycloak.fed_issued_ver_credential USING btree (storage_provider_id);


--
-- Name: idx_fed_issued_vc_user; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fed_issued_vc_user ON schema_keycloak.fed_issued_ver_credential USING btree (user_id, realm_id, issued_at);


--
-- Name: idx_fed_user_vc_realm_user; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fed_user_vc_realm_user ON schema_keycloak.fed_user_ver_credential USING btree (realm_id, user_id);


--
-- Name: idx_fedidentity_feduser; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fedidentity_feduser ON schema_keycloak.federated_identity USING btree (federated_user_id);


--
-- Name: idx_fedidentity_user; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fedidentity_user ON schema_keycloak.federated_identity USING btree (user_id);


--
-- Name: idx_fu_attribute; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fu_attribute ON schema_keycloak.fed_user_attribute USING btree (user_id, realm_id, name);


--
-- Name: idx_fu_cnsnt_ext; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fu_cnsnt_ext ON schema_keycloak.fed_user_consent USING btree (user_id, client_storage_provider, external_client_id);


--
-- Name: idx_fu_consent; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fu_consent ON schema_keycloak.fed_user_consent USING btree (user_id, client_id);


--
-- Name: idx_fu_consent_ru; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fu_consent_ru ON schema_keycloak.fed_user_consent USING btree (realm_id, user_id);


--
-- Name: idx_fu_credential; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fu_credential ON schema_keycloak.fed_user_credential USING btree (user_id, type);


--
-- Name: idx_fu_credential_ru; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fu_credential_ru ON schema_keycloak.fed_user_credential USING btree (realm_id, user_id);


--
-- Name: idx_fu_group_membership; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fu_group_membership ON schema_keycloak.fed_user_group_membership USING btree (user_id, group_id);


--
-- Name: idx_fu_group_membership_ru; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fu_group_membership_ru ON schema_keycloak.fed_user_group_membership USING btree (realm_id, user_id);


--
-- Name: idx_fu_required_action; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fu_required_action ON schema_keycloak.fed_user_required_action USING btree (user_id, required_action);


--
-- Name: idx_fu_required_action_ru; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fu_required_action_ru ON schema_keycloak.fed_user_required_action USING btree (realm_id, user_id);


--
-- Name: idx_fu_role_mapping; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fu_role_mapping ON schema_keycloak.fed_user_role_mapping USING btree (user_id, role_id);


--
-- Name: idx_fu_role_mapping_ru; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_fu_role_mapping_ru ON schema_keycloak.fed_user_role_mapping USING btree (realm_id, user_id);


--
-- Name: idx_group_att_by_name_value; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_group_att_by_name_value ON schema_keycloak.group_attribute USING btree (name, ((value)::character varying(250)));


--
-- Name: idx_group_attr_group; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_group_attr_group ON schema_keycloak.group_attribute USING btree (group_id);


--
-- Name: idx_group_org_id; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_group_org_id ON schema_keycloak.keycloak_group USING btree (org_id);


--
-- Name: idx_group_role_mapp_group; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_group_role_mapp_group ON schema_keycloak.group_role_mapping USING btree (group_id);


--
-- Name: idx_id_prov_mapp_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_id_prov_mapp_realm ON schema_keycloak.identity_provider_mapper USING btree (realm_id);


--
-- Name: idx_ident_prov_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_ident_prov_realm ON schema_keycloak.identity_provider USING btree (realm_id);


--
-- Name: idx_idp_for_login; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_idp_for_login ON schema_keycloak.identity_provider USING btree (realm_id, enabled, link_only, hide_on_login, organization_id);


--
-- Name: idx_idp_realm_org; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_idp_realm_org ON schema_keycloak.identity_provider USING btree (realm_id, organization_id);


--
-- Name: idx_issued_ver_credential_expires_at; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_issued_ver_credential_expires_at ON schema_keycloak.issued_ver_credential USING btree (expires_at);


--
-- Name: idx_issued_ver_credential_user; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_issued_ver_credential_user ON schema_keycloak.issued_ver_credential USING btree (user_id, issued_at);


--
-- Name: idx_issued_ver_credential_vc; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_issued_ver_credential_vc ON schema_keycloak.issued_ver_credential USING btree (ver_credential_id);


--
-- Name: idx_keycloak_role_client; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_keycloak_role_client ON schema_keycloak.keycloak_role USING btree (client);


--
-- Name: idx_keycloak_role_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_keycloak_role_realm ON schema_keycloak.keycloak_role USING btree (realm);


--
-- Name: idx_login_failure_expire; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_login_failure_expire ON schema_keycloak.login_failure USING btree (last_failure);


--
-- Name: idx_offline_css_by_client; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_offline_css_by_client ON schema_keycloak.offline_client_session USING btree (client_id, offline_flag) WHERE ((client_id)::text <> 'external'::text);


--
-- Name: idx_offline_css_by_client_and_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_offline_css_by_client_and_realm ON schema_keycloak.offline_client_session USING btree (realm_id, offline_flag, client_id, client_storage_provider, external_client_id);


--
-- Name: idx_offline_css_by_client_storage_provider; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_offline_css_by_client_storage_provider ON schema_keycloak.offline_client_session USING btree (client_storage_provider, external_client_id, offline_flag) WHERE ((client_storage_provider)::text <> 'internal'::text);


--
-- Name: idx_offline_css_by_user_session_and_offline; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_offline_css_by_user_session_and_offline ON schema_keycloak.offline_client_session USING btree (offline_flag, user_session_id);


--
-- Name: idx_offline_uss_by_broker_session_id; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_offline_uss_by_broker_session_id ON schema_keycloak.offline_user_session USING btree (broker_session_id, realm_id);


--
-- Name: idx_offline_uss_by_user; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_offline_uss_by_user ON schema_keycloak.offline_user_session USING btree (user_id, realm_id, offline_flag);


--
-- Name: idx_org_domain_org_id; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_org_domain_org_id ON schema_keycloak.org_domain USING btree (org_id);


--
-- Name: idx_org_invitation_email; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_org_invitation_email ON schema_keycloak.org_invitation USING btree (email);


--
-- Name: idx_org_invitation_expires; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_org_invitation_expires ON schema_keycloak.org_invitation USING btree (expires_at);


--
-- Name: idx_org_invitation_org_id; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_org_invitation_org_id ON schema_keycloak.org_invitation USING btree (organization_id);


--
-- Name: idx_outbox_container; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_outbox_container ON schema_keycloak.outbox_entry USING btree (entry_kind, owner_id, container_id);


--
-- Name: idx_outbox_drain; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_outbox_drain ON schema_keycloak.outbox_entry USING btree (entry_kind, status, next_attempt_at);


--
-- Name: idx_outbox_owner; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_outbox_owner ON schema_keycloak.outbox_entry USING btree (entry_kind, owner_id, status);


--
-- Name: idx_outbox_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_outbox_realm ON schema_keycloak.outbox_entry USING btree (entry_kind, realm_id, status);


--
-- Name: idx_perm_ticket_owner; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_perm_ticket_owner ON schema_keycloak.resource_server_perm_ticket USING btree (owner);


--
-- Name: idx_perm_ticket_requester; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_perm_ticket_requester ON schema_keycloak.resource_server_perm_ticket USING btree (requester);


--
-- Name: idx_protocol_mapper_client; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_protocol_mapper_client ON schema_keycloak.protocol_mapper USING btree (client_id);


--
-- Name: idx_realm_attr_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_realm_attr_realm ON schema_keycloak.realm_attribute USING btree (realm_id);


--
-- Name: idx_realm_clscope; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_realm_clscope ON schema_keycloak.client_scope USING btree (realm_id);


--
-- Name: idx_realm_def_grp_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_realm_def_grp_realm ON schema_keycloak.realm_default_groups USING btree (realm_id);


--
-- Name: idx_realm_evt_list_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_realm_evt_list_realm ON schema_keycloak.realm_events_listeners USING btree (realm_id);


--
-- Name: idx_realm_evt_types_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_realm_evt_types_realm ON schema_keycloak.realm_enabled_event_types USING btree (realm_id);


--
-- Name: idx_realm_master_adm_cli; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_realm_master_adm_cli ON schema_keycloak.realm USING btree (master_admin_client);


--
-- Name: idx_realm_supp_local_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_realm_supp_local_realm ON schema_keycloak.realm_supported_locales USING btree (realm_id);


--
-- Name: idx_redir_uri_client; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_redir_uri_client ON schema_keycloak.redirect_uris USING btree (client_id);


--
-- Name: idx_req_act_prov_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_req_act_prov_realm ON schema_keycloak.required_action_provider USING btree (realm_id);


--
-- Name: idx_res_policy_policy; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_res_policy_policy ON schema_keycloak.resource_policy USING btree (policy_id);


--
-- Name: idx_res_scope_scope; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_res_scope_scope ON schema_keycloak.resource_scope USING btree (scope_id);


--
-- Name: idx_res_serv_pol_res_serv; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_res_serv_pol_res_serv ON schema_keycloak.resource_server_policy USING btree (resource_server_id);


--
-- Name: idx_res_srv_res_res_srv; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_res_srv_res_res_srv ON schema_keycloak.resource_server_resource USING btree (resource_server_id);


--
-- Name: idx_res_srv_scope_res_srv; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_res_srv_scope_res_srv ON schema_keycloak.resource_server_scope USING btree (resource_server_id);


--
-- Name: idx_rev_token_on_expire; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_rev_token_on_expire ON schema_keycloak.revoked_token USING btree (expire);


--
-- Name: idx_role_attribute; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_role_attribute ON schema_keycloak.role_attribute USING btree (role_id);


--
-- Name: idx_role_clscope; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_role_clscope ON schema_keycloak.client_scope_role_mapping USING btree (role_id);


--
-- Name: idx_root_auth_session_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_root_auth_session_realm ON schema_keycloak.root_auth_session USING btree (realm_id, "timestamp");


--
-- Name: idx_scope_mapping_role; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_scope_mapping_role ON schema_keycloak.scope_mapping USING btree (role_id);


--
-- Name: idx_scope_policy_policy; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_scope_policy_policy ON schema_keycloak.scope_policy USING btree (policy_id);


--
-- Name: idx_single_use_obj_expire; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_single_use_obj_expire ON schema_keycloak.single_use_object USING btree (expire);


--
-- Name: idx_update_time; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_update_time ON schema_keycloak.migration_model USING btree (update_time);


--
-- Name: idx_usconsent_clscope; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_usconsent_clscope ON schema_keycloak.user_consent_client_scope USING btree (user_consent_id);


--
-- Name: idx_usconsent_scope_id; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_usconsent_scope_id ON schema_keycloak.user_consent_client_scope USING btree (scope_id);


--
-- Name: idx_user_attribute; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_user_attribute ON schema_keycloak.user_attribute USING btree (user_id);


--
-- Name: idx_user_attribute_name; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_user_attribute_name ON schema_keycloak.user_attribute USING btree (name, value);


--
-- Name: idx_user_consent; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_user_consent ON schema_keycloak.user_consent USING btree (user_id);


--
-- Name: idx_user_created_timestamp; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_user_created_timestamp ON schema_keycloak.user_entity USING btree (realm_id, created_timestamp);


--
-- Name: idx_user_credential; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_user_credential ON schema_keycloak.credential USING btree (user_id);


--
-- Name: idx_user_email; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_user_email ON schema_keycloak.user_entity USING btree (email);


--
-- Name: idx_user_group_mapping; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_user_group_mapping ON schema_keycloak.user_group_membership USING btree (user_id);


--
-- Name: idx_user_reqactions; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_user_reqactions ON schema_keycloak.user_required_action USING btree (user_id);


--
-- Name: idx_user_role_mapping; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_user_role_mapping ON schema_keycloak.user_role_mapping USING btree (user_id);


--
-- Name: idx_user_service_account; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_user_service_account ON schema_keycloak.user_entity USING btree (realm_id, service_account_client_link);


--
-- Name: idx_user_session_expiration_created; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_user_session_expiration_created ON schema_keycloak.offline_user_session USING btree (realm_id, offline_flag, remember_me, created_on, user_session_id, user_id);


--
-- Name: idx_user_session_expiration_last_refresh; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_user_session_expiration_last_refresh ON schema_keycloak.offline_user_session USING btree (realm_id, offline_flag, remember_me, last_session_refresh, user_session_id, user_id);


--
-- Name: idx_usr_fed_map_fed_prv; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_usr_fed_map_fed_prv ON schema_keycloak.user_federation_mapper USING btree (federation_provider_id);


--
-- Name: idx_usr_fed_map_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_usr_fed_map_realm ON schema_keycloak.user_federation_mapper USING btree (realm_id);


--
-- Name: idx_usr_fed_prv_realm; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_usr_fed_prv_realm ON schema_keycloak.user_federation_provider USING btree (realm_id);


--
-- Name: idx_web_orig_client; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_web_orig_client ON schema_keycloak.web_origins USING btree (client_id);


--
-- Name: idx_workflow_state_provider; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_workflow_state_provider ON schema_keycloak.workflow_state USING btree (resource_id);


--
-- Name: idx_workflow_state_step; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX idx_workflow_state_step ON schema_keycloak.workflow_state USING btree (workflow_id, scheduled_step_id);


--
-- Name: user_attr_long_values; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX user_attr_long_values ON schema_keycloak.user_attribute USING btree (long_value_hash, name);


--
-- Name: user_attr_long_values_lower_case; Type: INDEX; Schema: schema_keycloak; Owner: postgres
--

CREATE INDEX user_attr_long_values_lower_case ON schema_keycloak.user_attribute USING btree (long_value_hash_lower_case, name);


--
-- Name: crm_lead_history fk1vam2k1o58bixtutqenner87d; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_lead_history
    ADD CONSTRAINT fk1vam2k1o58bixtutqenner87d FOREIGN KEY (lead_id) REFERENCES schema_crm.crm_lead(lead_id);


--
-- Name: crm_lead_history fk4k8ke7osic0v5g70l5gmfxqq7; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_lead_history
    ADD CONSTRAINT fk4k8ke7osic0v5g70l5gmfxqq7 FOREIGN KEY (new_stage_id) REFERENCES schema_crm.crm_stage(stage_id);


--
-- Name: crm_lead_history fk693gsqfwfnxedfly4igq0i06c; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crm_lead_history
    ADD CONSTRAINT fk693gsqfwfnxedfly4igq0i06c FOREIGN KEY (old_stage_id) REFERENCES schema_crm.crm_stage(stage_id);


--
-- Name: adm_mst_user_role adm_mst_user_role_fk_role; Type: FK CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_role
    ADD CONSTRAINT adm_mst_user_role_fk_role FOREIGN KEY (dmur_role_id) REFERENCES schema_admin.adm_mst_role(dmrole_id);


--
-- Name: adm_mst_user_role adm_mst_user_role_fk_user; Type: FK CONSTRAINT; Schema: schema_admin; Owner: postgres
--

ALTER TABLE ONLY schema_admin.adm_mst_user_role
    ADD CONSTRAINT adm_mst_user_role_fk_user FOREIGN KEY (dmur_user_id) REFERENCES schema_admin.adm_mst_user_application(dmuapp_id);


--
-- Name: crm_activity crm_activity_activity_type_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_activity
    ADD CONSTRAINT crm_activity_activity_type_id_fkey FOREIGN KEY (activity_type_id) REFERENCES schema_crm.crm_activity_type(activity_type_id);


--
-- Name: crm_activity crm_activity_lead_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_activity
    ADD CONSTRAINT crm_activity_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES schema_crm.crm_lead(lead_id) ON DELETE CASCADE;


--
-- Name: crm_interaction_log crm_interaction_log_activity_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_interaction_log
    ADD CONSTRAINT crm_interaction_log_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES schema_crm.crm_activity(activity_id);


--
-- Name: crm_interaction_log crm_interaction_log_lead_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_interaction_log
    ADD CONSTRAINT crm_interaction_log_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES schema_crm.crm_lead(lead_id) ON DELETE CASCADE;


--
-- Name: crm_interaction_log crm_interaction_log_user_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_interaction_log
    ADD CONSTRAINT crm_interaction_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES schema_crm.res_users(user_id);


--
-- Name: crm_lead crm_lead_campaign_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead
    ADD CONSTRAINT crm_lead_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES schema_crm.utm_campaign(campaign_id);


--
-- Name: crm_lead crm_lead_currency_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead
    ADD CONSTRAINT crm_lead_currency_id_fkey FOREIGN KEY (currency_id) REFERENCES schema_crm.res_currency(currency_id);


--
-- Name: crm_lead crm_lead_lead_source_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead
    ADD CONSTRAINT crm_lead_lead_source_id_fkey FOREIGN KEY (lead_source_id) REFERENCES schema_crm.crm_lead_source(lead_source_id);


--
-- Name: crm_lead crm_lead_lost_reason_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead
    ADD CONSTRAINT crm_lead_lost_reason_id_fkey FOREIGN KEY (lost_reason_id) REFERENCES schema_crm.crm_lost_reason(lost_reason_id);


--
-- Name: crm_lead crm_lead_medium_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead
    ADD CONSTRAINT crm_lead_medium_id_fkey FOREIGN KEY (medium_id) REFERENCES schema_crm.utm_medium(medium_id);


--
-- Name: crm_lead crm_lead_partner_contact_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead
    ADD CONSTRAINT crm_lead_partner_contact_id_fkey FOREIGN KEY (partner_contact_id) REFERENCES schema_crm.res_partner_contact(contact_id);


--
-- Name: crm_lead crm_lead_partner_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead
    ADD CONSTRAINT crm_lead_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES schema_crm.res_partner(partner_id);


--
-- Name: crm_lead crm_lead_sales_team_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead
    ADD CONSTRAINT crm_lead_sales_team_id_fkey FOREIGN KEY (sales_team_id) REFERENCES schema_crm.sales_team(team_id);


--
-- Name: crm_lead crm_lead_source_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead
    ADD CONSTRAINT crm_lead_source_id_fkey FOREIGN KEY (source_id) REFERENCES schema_crm.utm_source(source_id);


--
-- Name: crm_lead crm_lead_stage_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead
    ADD CONSTRAINT crm_lead_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES schema_crm.crm_stage(stage_id);


--
-- Name: crm_lead crm_lead_user_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead
    ADD CONSTRAINT crm_lead_user_id_fkey FOREIGN KEY (user_id) REFERENCES schema_crm.res_users(user_id);


--
-- Name: crm_ticket_conversations crm_ticket_conversations_ticket_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_ticket_conversations
    ADD CONSTRAINT crm_ticket_conversations_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES schema_crm.crm_tickets(ticket_id) ON DELETE CASCADE;


--
-- Name: crm_ticket_conversations crm_ticket_conversations_user_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_ticket_conversations
    ADD CONSTRAINT crm_ticket_conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES schema_crm.res_users(user_id);


--
-- Name: crm_tickets crm_tickets_assigned_to_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_tickets
    ADD CONSTRAINT crm_tickets_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES schema_crm.res_users(user_id);


--
-- Name: crm_tickets crm_tickets_partner_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_tickets
    ADD CONSTRAINT crm_tickets_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES schema_crm.res_partner(partner_id);


--
-- Name: sales_targets fk3lb2334ugujcix5pwqj0ab0dm; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.sales_targets
    ADD CONSTRAINT fk3lb2334ugujcix5pwqj0ab0dm FOREIGN KEY (user_id) REFERENCES schema_crm.res_users(user_id);


--
-- Name: crm_monthly_target fk9wwwo3c6yhj7h5hxxbb20my4l; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_monthly_target
    ADD CONSTRAINT fk9wwwo3c6yhj7h5hxxbb20my4l FOREIGN KEY (user_id) REFERENCES schema_crm.res_users(user_id);


--
-- Name: crm_lead_history fk_history_lead; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead_history
    ADD CONSTRAINT fk_history_lead FOREIGN KEY (lead_id) REFERENCES schema_crm.crm_lead(lead_id) ON DELETE CASCADE;


--
-- Name: crm_lead_history fk_history_new_stage; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead_history
    ADD CONSTRAINT fk_history_new_stage FOREIGN KEY (new_stage_id) REFERENCES schema_crm.crm_stage(stage_id) ON DELETE SET NULL;


--
-- Name: crm_lead_history fk_history_old_stage; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_lead_history
    ADD CONSTRAINT fk_history_old_stage FOREIGN KEY (old_stage_id) REFERENCES schema_crm.crm_stage(stage_id) ON DELETE SET NULL;


--
-- Name: crm_activity fkajg4dg461o3rqhtutkh6o9w4y; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.crm_activity
    ADD CONSTRAINT fkajg4dg461o3rqhtutkh6o9w4y FOREIGN KEY (user_id) REFERENCES schema_crm.res_users(user_id);


--
-- Name: hr_employee hr_employee_job_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.hr_employee
    ADD CONSTRAINT hr_employee_job_id_fkey FOREIGN KEY (job_id) REFERENCES schema_crm.hr_job(job_id);


--
-- Name: lead_competitor_rel lead_competitor_rel_competitor_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.lead_competitor_rel
    ADD CONSTRAINT lead_competitor_rel_competitor_id_fkey FOREIGN KEY (competitor_id) REFERENCES schema_crm.crm_competitor(competitor_id) ON DELETE CASCADE;


--
-- Name: lead_competitor_rel lead_competitor_rel_lead_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.lead_competitor_rel
    ADD CONSTRAINT lead_competitor_rel_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES schema_crm.crm_lead(lead_id) ON DELETE CASCADE;


--
-- Name: mail_message mail_message_author_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.mail_message
    ADD CONSTRAINT mail_message_author_id_fkey FOREIGN KEY (author_id) REFERENCES schema_crm.res_partner(partner_id);


--
-- Name: res_partner res_partner_category_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_partner
    ADD CONSTRAINT res_partner_category_id_fkey FOREIGN KEY (category_id) REFERENCES schema_crm.res_partner_category(category_id);


--
-- Name: res_partner_contact res_partner_contact_partner_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_partner_contact
    ADD CONSTRAINT res_partner_contact_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES schema_crm.res_partner(partner_id) ON DELETE CASCADE;


--
-- Name: res_partner res_partner_parent_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_partner
    ADD CONSTRAINT res_partner_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES schema_crm.res_partner(partner_id);


--
-- Name: res_users res_users_employee_id_fkey; Type: FK CONSTRAINT; Schema: schema_crm; Owner: postgres
--

ALTER TABLE ONLY schema_crm.res_users
    ADD CONSTRAINT res_users_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES schema_crm.hr_employee(employee_id);


--
-- Name: hr_mst_attendance_rule fk_att_rule_company; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_attendance_rule
    ADD CONSTRAINT fk_att_rule_company FOREIGN KEY (dcomp_id) REFERENCES schema_hrd.hr_mst_company_config(dcomp_id);


--
-- Name: hr_mst_employee fk_emp_company; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee
    ADD CONSTRAINT fk_emp_company FOREIGN KEY (dcomp_id) REFERENCES schema_hrd.hr_mst_company_config(dcomp_id);


--
-- Name: hr_mst_employee_payroll_config fk_emp_config_emp; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee_payroll_config
    ADD CONSTRAINT fk_emp_config_emp FOREIGN KEY (depc_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_mst_employee fk_emp_grade; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee
    ADD CONSTRAINT fk_emp_grade FOREIGN KEY (dmemp_grade_id) REFERENCES schema_hrd.hr_mst_job_grade(dgrade_id);


--
-- Name: hr_txn_employee_payroll_rule fk_emp_rule_employee; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_payroll_rule
    ADD CONSTRAINT fk_emp_rule_employee FOREIGN KEY (depr_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_txn_employee_payroll_rule fk_emp_rule_rule; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_payroll_rule
    ADD CONSTRAINT fk_emp_rule_rule FOREIGN KEY (depr_rule_id) REFERENCES schema_hrd.hr_mst_payroll_rule(drule_id);


--
-- Name: hr_txn_loan fk_loan_type; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_loan
    ADD CONSTRAINT fk_loan_type FOREIGN KEY (dloant_id) REFERENCES schema_hrd.hr_mst_loan_type(dloant_id);


--
-- Name: hr_txn_payslip fk_payslip_period; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_payslip
    ADD CONSTRAINT fk_payslip_period FOREIGN KEY (dper_id) REFERENCES schema_hrd.hr_mst_payroll_period(dper_id);


--
-- Name: hr_txn_employee_shift fk_shift_employee; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_shift
    ADD CONSTRAINT fk_shift_employee FOREIGN KEY (deshift_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_txn_employee_shift fk_shift_master; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_shift
    ADD CONSTRAINT fk_shift_master FOREIGN KEY (deshift_shift_id) REFERENCES schema_hrd.hr_mst_shift(dshift_id);


--
-- Name: hr_mst_employee_tax fk_tax_employee; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee_tax
    ADD CONSTRAINT fk_tax_employee FOREIGN KEY (detax_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_mst_employee hr_mst_employee_fk_dept; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee
    ADD CONSTRAINT hr_mst_employee_fk_dept FOREIGN KEY (dmemp_department_id) REFERENCES schema_hrd.hr_mst_department(dmdep_id);


--
-- Name: hr_mst_employee hr_mst_employee_fk_mgr; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee
    ADD CONSTRAINT hr_mst_employee_fk_mgr FOREIGN KEY (dmemp_manager_id) REFERENCES schema_hrd.hr_mst_employee(dmemp_id);


--
-- Name: hr_mst_employee hr_mst_employee_fk_pos; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_mst_employee
    ADD CONSTRAINT hr_mst_employee_fk_pos FOREIGN KEY (dmemp_position_id) REFERENCES schema_hrd.hr_mst_position(dmpos_id);


--
-- Name: hr_txn_attendance hr_txn_attendance_fk_emp; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_attendance
    ADD CONSTRAINT hr_txn_attendance_fk_emp FOREIGN KEY (dmatn_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_txn_career_history hr_txn_career_history_fk_emp; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_career_history
    ADD CONSTRAINT hr_txn_career_history_fk_emp FOREIGN KEY (dmcar_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_txn_career_history hr_txn_career_history_fk_new_dept; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_career_history
    ADD CONSTRAINT hr_txn_career_history_fk_new_dept FOREIGN KEY (dmcar_new_department_id) REFERENCES schema_hrd.hr_mst_department(dmdep_id);


--
-- Name: hr_txn_career_history hr_txn_career_history_fk_new_pos; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_career_history
    ADD CONSTRAINT hr_txn_career_history_fk_new_pos FOREIGN KEY (dmcar_new_position_id) REFERENCES schema_hrd.hr_mst_position(dmpos_id);


--
-- Name: hr_txn_career_history hr_txn_career_history_fk_old_dept; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_career_history
    ADD CONSTRAINT hr_txn_career_history_fk_old_dept FOREIGN KEY (dmcar_old_department_id) REFERENCES schema_hrd.hr_mst_department(dmdep_id);


--
-- Name: hr_txn_career_history hr_txn_career_history_fk_old_pos; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_career_history
    ADD CONSTRAINT hr_txn_career_history_fk_old_pos FOREIGN KEY (dmcar_old_position_id) REFERENCES schema_hrd.hr_mst_position(dmpos_id);


--
-- Name: hr_txn_contract hr_txn_contract_fk_emp; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_contract
    ADD CONSTRAINT hr_txn_contract_fk_emp FOREIGN KEY (dmcon_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_txn_document hr_txn_document_fk_emp; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_document
    ADD CONSTRAINT hr_txn_document_fk_emp FOREIGN KEY (dmdoc_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_txn_employee_salary_detail hr_txn_employee_salary_detail_fk_comp; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_salary_detail
    ADD CONSTRAINT hr_txn_employee_salary_detail_fk_comp FOREIGN KEY (dmsald_component_id) REFERENCES schema_hrd.hr_mst_salary_component(dmsc_id);


--
-- Name: hr_txn_employee_salary_detail hr_txn_employee_salary_detail_fk_sal; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_salary_detail
    ADD CONSTRAINT hr_txn_employee_salary_detail_fk_sal FOREIGN KEY (dmsald_salary_id) REFERENCES schema_hrd.hr_txn_employee_salary(dmsal_id) ON DELETE CASCADE;


--
-- Name: hr_txn_employee_salary hr_txn_employee_salary_fk_emp; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_employee_salary
    ADD CONSTRAINT hr_txn_employee_salary_fk_emp FOREIGN KEY (dmsal_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_txn_leave_balance hr_txn_leave_balance_fk_emp; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_leave_balance
    ADD CONSTRAINT hr_txn_leave_balance_fk_emp FOREIGN KEY (dmlbal_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_txn_leave_balance hr_txn_leave_balance_fk_lty; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_leave_balance
    ADD CONSTRAINT hr_txn_leave_balance_fk_lty FOREIGN KEY (dmlbal_leave_type_id) REFERENCES schema_hrd.hr_mst_leave_type(dmlty_id);


--
-- Name: hr_txn_leave_request hr_txn_leave_request_fk_emp; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_leave_request
    ADD CONSTRAINT hr_txn_leave_request_fk_emp FOREIGN KEY (dmlreq_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_txn_leave_request hr_txn_leave_request_fk_lty; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_leave_request
    ADD CONSTRAINT hr_txn_leave_request_fk_lty FOREIGN KEY (dmlreq_leave_type_id) REFERENCES schema_hrd.hr_mst_leave_type(dmlty_id);


--
-- Name: hr_txn_loan hr_txn_loan_fk_emp; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_loan
    ADD CONSTRAINT hr_txn_loan_fk_emp FOREIGN KEY (dmlon_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_txn_overtime hr_txn_overtime_fk_att; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_overtime
    ADD CONSTRAINT hr_txn_overtime_fk_att FOREIGN KEY (dmovt_attendance_id) REFERENCES schema_hrd.hr_txn_attendance(dmatn_id);


--
-- Name: hr_txn_overtime hr_txn_overtime_fk_emp; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_overtime
    ADD CONSTRAINT hr_txn_overtime_fk_emp FOREIGN KEY (dmovt_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_txn_payslip hr_txn_payslip_fk_emp; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_payslip
    ADD CONSTRAINT hr_txn_payslip_fk_emp FOREIGN KEY (dmps_employee_code) REFERENCES schema_hrd.hr_mst_employee(dmemp_employee_code);


--
-- Name: hr_txn_payslip_line hr_txn_payslip_line_fk_comp; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_payslip_line
    ADD CONSTRAINT hr_txn_payslip_line_fk_comp FOREIGN KEY (dmpsl_component_id) REFERENCES schema_hrd.hr_mst_salary_component(dmsc_id);


--
-- Name: hr_txn_payslip_line hr_txn_payslip_line_fk_ps; Type: FK CONSTRAINT; Schema: schema_hrd; Owner: postgres
--

ALTER TABLE ONLY schema_hrd.hr_txn_payslip_line
    ADD CONSTRAINT hr_txn_payslip_line_fk_ps FOREIGN KEY (dmpsl_payslip_id) REFERENCES schema_hrd.hr_txn_payslip(dmps_id) ON DELETE CASCADE;


--
-- Name: identity_provider fk2b4ebc52ae5c3b34; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.identity_provider
    ADD CONSTRAINT fk2b4ebc52ae5c3b34 FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: client_attributes fk3c47c64beacca966; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_attributes
    ADD CONSTRAINT fk3c47c64beacca966 FOREIGN KEY (client_id) REFERENCES schema_keycloak.client(id);


--
-- Name: federated_identity fk404288b92ef007a6; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.federated_identity
    ADD CONSTRAINT fk404288b92ef007a6 FOREIGN KEY (user_id) REFERENCES schema_keycloak.user_entity(id);


--
-- Name: client_node_registrations fk4129723ba992f594; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_node_registrations
    ADD CONSTRAINT fk4129723ba992f594 FOREIGN KEY (client_id) REFERENCES schema_keycloak.client(id);


--
-- Name: redirect_uris fk_1burs8pb4ouj97h5wuppahv9f; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.redirect_uris
    ADD CONSTRAINT fk_1burs8pb4ouj97h5wuppahv9f FOREIGN KEY (client_id) REFERENCES schema_keycloak.client(id);


--
-- Name: user_federation_provider fk_1fj32f6ptolw2qy60cd8n01e8; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_federation_provider
    ADD CONSTRAINT fk_1fj32f6ptolw2qy60cd8n01e8 FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: realm_required_credential fk_5hg65lybevavkqfki3kponh9v; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_required_credential
    ADD CONSTRAINT fk_5hg65lybevavkqfki3kponh9v FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: resource_attribute fk_5hrm2vlf9ql5fu022kqepovbr; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_attribute
    ADD CONSTRAINT fk_5hrm2vlf9ql5fu022kqepovbr FOREIGN KEY (resource_id) REFERENCES schema_keycloak.resource_server_resource(id);


--
-- Name: user_attribute fk_5hrm2vlf9ql5fu043kqepovbr; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_attribute
    ADD CONSTRAINT fk_5hrm2vlf9ql5fu043kqepovbr FOREIGN KEY (user_id) REFERENCES schema_keycloak.user_entity(id);


--
-- Name: user_required_action fk_6qj3w1jw9cvafhe19bwsiuvmd; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_required_action
    ADD CONSTRAINT fk_6qj3w1jw9cvafhe19bwsiuvmd FOREIGN KEY (user_id) REFERENCES schema_keycloak.user_entity(id);


--
-- Name: keycloak_role fk_6vyqfe4cn4wlq8r6kt5vdsj5c; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.keycloak_role
    ADD CONSTRAINT fk_6vyqfe4cn4wlq8r6kt5vdsj5c FOREIGN KEY (realm) REFERENCES schema_keycloak.realm(id);


--
-- Name: realm_smtp_config fk_70ej8xdxgxd0b9hh6180irr0o; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_smtp_config
    ADD CONSTRAINT fk_70ej8xdxgxd0b9hh6180irr0o FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: realm_attribute fk_8shxd6l3e9atqukacxgpffptw; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_attribute
    ADD CONSTRAINT fk_8shxd6l3e9atqukacxgpffptw FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: composite_role fk_a63wvekftu8jo1pnj81e7mce2; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.composite_role
    ADD CONSTRAINT fk_a63wvekftu8jo1pnj81e7mce2 FOREIGN KEY (composite) REFERENCES schema_keycloak.keycloak_role(id);


--
-- Name: authentication_execution fk_auth_exec_flow; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.authentication_execution
    ADD CONSTRAINT fk_auth_exec_flow FOREIGN KEY (flow_id) REFERENCES schema_keycloak.authentication_flow(id);


--
-- Name: authentication_execution fk_auth_exec_realm; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.authentication_execution
    ADD CONSTRAINT fk_auth_exec_realm FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: authentication_flow fk_auth_flow_realm; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.authentication_flow
    ADD CONSTRAINT fk_auth_flow_realm FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: authenticator_config fk_auth_realm; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.authenticator_config
    ADD CONSTRAINT fk_auth_realm FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: auth_session fk_auth_session_root; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.auth_session
    ADD CONSTRAINT fk_auth_session_root FOREIGN KEY (root_auth_session_id) REFERENCES schema_keycloak.root_auth_session(id) ON DELETE CASCADE;


--
-- Name: user_role_mapping fk_c4fqv34p1mbylloxang7b1q3l; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_role_mapping
    ADD CONSTRAINT fk_c4fqv34p1mbylloxang7b1q3l FOREIGN KEY (user_id) REFERENCES schema_keycloak.user_entity(id);


--
-- Name: client_scope_attributes fk_cl_scope_attr_scope; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_scope_attributes
    ADD CONSTRAINT fk_cl_scope_attr_scope FOREIGN KEY (scope_id) REFERENCES schema_keycloak.client_scope(id);


--
-- Name: client_scope_role_mapping fk_cl_scope_rm_scope; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_scope_role_mapping
    ADD CONSTRAINT fk_cl_scope_rm_scope FOREIGN KEY (scope_id) REFERENCES schema_keycloak.client_scope(id);


--
-- Name: protocol_mapper fk_cli_scope_mapper; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.protocol_mapper
    ADD CONSTRAINT fk_cli_scope_mapper FOREIGN KEY (client_scope_id) REFERENCES schema_keycloak.client_scope(id);


--
-- Name: client_initial_access fk_client_init_acc_realm; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.client_initial_access
    ADD CONSTRAINT fk_client_init_acc_realm FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: component_config fk_component_config; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.component_config
    ADD CONSTRAINT fk_component_config FOREIGN KEY (component_id) REFERENCES schema_keycloak.component(id);


--
-- Name: component fk_component_realm; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.component
    ADD CONSTRAINT fk_component_realm FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: realm_default_groups fk_def_groups_realm; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_default_groups
    ADD CONSTRAINT fk_def_groups_realm FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: fed_issued_ver_credential fk_fed_issued_vc_ver_cred; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.fed_issued_ver_credential
    ADD CONSTRAINT fk_fed_issued_vc_ver_cred FOREIGN KEY (ver_credential_id) REFERENCES schema_keycloak.fed_user_ver_credential(id);


--
-- Name: user_federation_mapper_config fk_fedmapper_cfg; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_federation_mapper_config
    ADD CONSTRAINT fk_fedmapper_cfg FOREIGN KEY (user_federation_mapper_id) REFERENCES schema_keycloak.user_federation_mapper(id);


--
-- Name: user_federation_mapper fk_fedmapperpm_fedprv; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_federation_mapper
    ADD CONSTRAINT fk_fedmapperpm_fedprv FOREIGN KEY (federation_provider_id) REFERENCES schema_keycloak.user_federation_provider(id);


--
-- Name: user_federation_mapper fk_fedmapperpm_realm; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_federation_mapper
    ADD CONSTRAINT fk_fedmapperpm_realm FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: associated_policy fk_frsr5s213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.associated_policy
    ADD CONSTRAINT fk_frsr5s213xcx4wnkog82ssrfy FOREIGN KEY (associated_policy_id) REFERENCES schema_keycloak.resource_server_policy(id);


--
-- Name: scope_policy fk_frsrasp13xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.scope_policy
    ADD CONSTRAINT fk_frsrasp13xcx4wnkog82ssrfy FOREIGN KEY (policy_id) REFERENCES schema_keycloak.resource_server_policy(id);


--
-- Name: resource_server_perm_ticket fk_frsrho213xcx4wnkog82sspmt; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_perm_ticket
    ADD CONSTRAINT fk_frsrho213xcx4wnkog82sspmt FOREIGN KEY (resource_server_id) REFERENCES schema_keycloak.resource_server(id);


--
-- Name: resource_server_resource fk_frsrho213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_resource
    ADD CONSTRAINT fk_frsrho213xcx4wnkog82ssrfy FOREIGN KEY (resource_server_id) REFERENCES schema_keycloak.resource_server(id);


--
-- Name: resource_server_perm_ticket fk_frsrho213xcx4wnkog83sspmt; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_perm_ticket
    ADD CONSTRAINT fk_frsrho213xcx4wnkog83sspmt FOREIGN KEY (resource_id) REFERENCES schema_keycloak.resource_server_resource(id);


--
-- Name: resource_server_perm_ticket fk_frsrho213xcx4wnkog84sspmt; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_perm_ticket
    ADD CONSTRAINT fk_frsrho213xcx4wnkog84sspmt FOREIGN KEY (scope_id) REFERENCES schema_keycloak.resource_server_scope(id);


--
-- Name: associated_policy fk_frsrpas14xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.associated_policy
    ADD CONSTRAINT fk_frsrpas14xcx4wnkog82ssrfy FOREIGN KEY (policy_id) REFERENCES schema_keycloak.resource_server_policy(id);


--
-- Name: scope_policy fk_frsrpass3xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.scope_policy
    ADD CONSTRAINT fk_frsrpass3xcx4wnkog82ssrfy FOREIGN KEY (scope_id) REFERENCES schema_keycloak.resource_server_scope(id);


--
-- Name: resource_server_perm_ticket fk_frsrpo2128cx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_perm_ticket
    ADD CONSTRAINT fk_frsrpo2128cx4wnkog82ssrfy FOREIGN KEY (policy_id) REFERENCES schema_keycloak.resource_server_policy(id);


--
-- Name: resource_server_policy fk_frsrpo213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_policy
    ADD CONSTRAINT fk_frsrpo213xcx4wnkog82ssrfy FOREIGN KEY (resource_server_id) REFERENCES schema_keycloak.resource_server(id);


--
-- Name: resource_scope fk_frsrpos13xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_scope
    ADD CONSTRAINT fk_frsrpos13xcx4wnkog82ssrfy FOREIGN KEY (resource_id) REFERENCES schema_keycloak.resource_server_resource(id);


--
-- Name: resource_policy fk_frsrpos53xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_policy
    ADD CONSTRAINT fk_frsrpos53xcx4wnkog82ssrfy FOREIGN KEY (resource_id) REFERENCES schema_keycloak.resource_server_resource(id);


--
-- Name: resource_policy fk_frsrpp213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_policy
    ADD CONSTRAINT fk_frsrpp213xcx4wnkog82ssrfy FOREIGN KEY (policy_id) REFERENCES schema_keycloak.resource_server_policy(id);


--
-- Name: resource_scope fk_frsrps213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_scope
    ADD CONSTRAINT fk_frsrps213xcx4wnkog82ssrfy FOREIGN KEY (scope_id) REFERENCES schema_keycloak.resource_server_scope(id);


--
-- Name: resource_server_scope fk_frsrso213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_server_scope
    ADD CONSTRAINT fk_frsrso213xcx4wnkog82ssrfy FOREIGN KEY (resource_server_id) REFERENCES schema_keycloak.resource_server(id);


--
-- Name: composite_role fk_gr7thllb9lu8q4vqa4524jjy8; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.composite_role
    ADD CONSTRAINT fk_gr7thllb9lu8q4vqa4524jjy8 FOREIGN KEY (child_role) REFERENCES schema_keycloak.keycloak_role(id);


--
-- Name: user_consent_client_scope fk_grntcsnt_clsc_usc; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_consent_client_scope
    ADD CONSTRAINT fk_grntcsnt_clsc_usc FOREIGN KEY (user_consent_id) REFERENCES schema_keycloak.user_consent(id);


--
-- Name: user_consent fk_grntcsnt_user; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_consent
    ADD CONSTRAINT fk_grntcsnt_user FOREIGN KEY (user_id) REFERENCES schema_keycloak.user_entity(id);


--
-- Name: group_attribute fk_group_attribute_group; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.group_attribute
    ADD CONSTRAINT fk_group_attribute_group FOREIGN KEY (group_id) REFERENCES schema_keycloak.keycloak_group(id);


--
-- Name: keycloak_group fk_group_organization; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.keycloak_group
    ADD CONSTRAINT fk_group_organization FOREIGN KEY (org_id) REFERENCES schema_keycloak.org(id);


--
-- Name: group_role_mapping fk_group_role_group; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.group_role_mapping
    ADD CONSTRAINT fk_group_role_group FOREIGN KEY (group_id) REFERENCES schema_keycloak.keycloak_group(id);


--
-- Name: realm_enabled_event_types fk_h846o4h0w8epx5nwedrf5y69j; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_enabled_event_types
    ADD CONSTRAINT fk_h846o4h0w8epx5nwedrf5y69j FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: realm_events_listeners fk_h846o4h0w8epx5nxev9f5y69j; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_events_listeners
    ADD CONSTRAINT fk_h846o4h0w8epx5nxev9f5y69j FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: identity_provider_mapper fk_idpm_realm; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.identity_provider_mapper
    ADD CONSTRAINT fk_idpm_realm FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: idp_mapper_config fk_idpmconfig; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.idp_mapper_config
    ADD CONSTRAINT fk_idpmconfig FOREIGN KEY (idp_mapper_id) REFERENCES schema_keycloak.identity_provider_mapper(id);


--
-- Name: issued_ver_credential fk_issued_ver_credential_user; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.issued_ver_credential
    ADD CONSTRAINT fk_issued_ver_credential_user FOREIGN KEY (user_id) REFERENCES schema_keycloak.user_entity(id);


--
-- Name: issued_ver_credential fk_issued_ver_credential_vc; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.issued_ver_credential
    ADD CONSTRAINT fk_issued_ver_credential_vc FOREIGN KEY (ver_credential_id) REFERENCES schema_keycloak.user_ver_credential(id);


--
-- Name: web_origins fk_lojpho213xcx4wnkog82ssrfy; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.web_origins
    ADD CONSTRAINT fk_lojpho213xcx4wnkog82ssrfy FOREIGN KEY (client_id) REFERENCES schema_keycloak.client(id);


--
-- Name: org_invitation fk_org_invitation_org; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.org_invitation
    ADD CONSTRAINT fk_org_invitation_org FOREIGN KEY (organization_id) REFERENCES schema_keycloak.org(id) ON DELETE CASCADE;


--
-- Name: scope_mapping fk_ouse064plmlr732lxjcn1q5f1; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.scope_mapping
    ADD CONSTRAINT fk_ouse064plmlr732lxjcn1q5f1 FOREIGN KEY (client_id) REFERENCES schema_keycloak.client(id);


--
-- Name: protocol_mapper fk_pcm_realm; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.protocol_mapper
    ADD CONSTRAINT fk_pcm_realm FOREIGN KEY (client_id) REFERENCES schema_keycloak.client(id);


--
-- Name: credential fk_pfyr0glasqyl0dei3kl69r6v0; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.credential
    ADD CONSTRAINT fk_pfyr0glasqyl0dei3kl69r6v0 FOREIGN KEY (user_id) REFERENCES schema_keycloak.user_entity(id);


--
-- Name: protocol_mapper_config fk_pmconfig; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.protocol_mapper_config
    ADD CONSTRAINT fk_pmconfig FOREIGN KEY (protocol_mapper_id) REFERENCES schema_keycloak.protocol_mapper(id);


--
-- Name: default_client_scope fk_r_def_cli_scope_realm; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.default_client_scope
    ADD CONSTRAINT fk_r_def_cli_scope_realm FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: required_action_provider fk_req_act_realm; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.required_action_provider
    ADD CONSTRAINT fk_req_act_realm FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: resource_uris fk_resource_server_uris; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.resource_uris
    ADD CONSTRAINT fk_resource_server_uris FOREIGN KEY (resource_id) REFERENCES schema_keycloak.resource_server_resource(id);


--
-- Name: role_attribute fk_role_attribute_id; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.role_attribute
    ADD CONSTRAINT fk_role_attribute_id FOREIGN KEY (role_id) REFERENCES schema_keycloak.keycloak_role(id);


--
-- Name: realm_supported_locales fk_supported_locales_realm; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.realm_supported_locales
    ADD CONSTRAINT fk_supported_locales_realm FOREIGN KEY (realm_id) REFERENCES schema_keycloak.realm(id);


--
-- Name: user_federation_config fk_t13hpu1j94r2ebpekr39x5eu5; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_federation_config
    ADD CONSTRAINT fk_t13hpu1j94r2ebpekr39x5eu5 FOREIGN KEY (user_federation_provider_id) REFERENCES schema_keycloak.user_federation_provider(id);


--
-- Name: user_group_membership fk_user_group_user; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_group_membership
    ADD CONSTRAINT fk_user_group_user FOREIGN KEY (user_id) REFERENCES schema_keycloak.user_entity(id);


--
-- Name: user_ver_credential fk_vcred_user; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.user_ver_credential
    ADD CONSTRAINT fk_vcred_user FOREIGN KEY (user_id) REFERENCES schema_keycloak.user_entity(id);


--
-- Name: policy_config fkdc34197cf864c4e43; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.policy_config
    ADD CONSTRAINT fkdc34197cf864c4e43 FOREIGN KEY (policy_id) REFERENCES schema_keycloak.resource_server_policy(id);


--
-- Name: identity_provider_config fkdc4897cf864c4e43; Type: FK CONSTRAINT; Schema: schema_keycloak; Owner: postgres
--

ALTER TABLE ONLY schema_keycloak.identity_provider_config
    ADD CONSTRAINT fkdc4897cf864c4e43 FOREIGN KEY (identity_provider_id) REFERENCES schema_keycloak.identity_provider(internal_id);


--
-- PostgreSQL database dump complete
--

