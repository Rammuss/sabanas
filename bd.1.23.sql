PGDMP                          }        
   bd_sabanas    10.23    15.2 o   /           0    0    ENCODING    ENCODING        SET client_encoding = 'UTF8';
                      false            0           0    0 
   STDSTRINGS 
   STDSTRINGS     (   SET standard_conforming_strings = 'on';
                      false            1           0    0 
   SEARCHPATH 
   SEARCHPATH     8   SELECT pg_catalog.set_config('search_path', '', false);
                      false            2           1262    17198 
   bd_sabanas    DATABASE     �   CREATE DATABASE bd_sabanas WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'English_United States.1252';
    DROP DATABASE bd_sabanas;
                postgres    false                        2615    2200    public    SCHEMA     2   -- *not* creating schema, since initdb creates it
 2   -- *not* dropping schema, since initdb creates it
                postgres    false            3           0    0    SCHEMA public    ACL     Q   REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO PUBLIC;
                   postgres    false    6            (           1255    19051    abrir_caja(numeric, integer)    FUNCTION     `  CREATE FUNCTION public.abrir_caja(monto_inicial numeric, usuario_id integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    caja_id INTEGER;
BEGIN
    -- Verificar si el usuario ya tiene una caja abierta
    IF EXISTS (
        SELECT 1 FROM cajas WHERE usuario = usuario_id AND estado = 'Abierta'
    ) THEN
        RETURN 'El usuario ya tiene una caja abierta. No puede abrir otra hasta cerrar la actual.';
    END IF;
    
    -- Insertar en la tabla de cajas con el monto inicial, el usuario que la abre, y la hora exacta de apertura
    INSERT INTO cajas (monto_inicial, estado, usuario, fecha_apertura, hora_apertura)
    VALUES (monto_inicial, 'Abierta', usuario_id, CURRENT_DATE, CURRENT_TIMESTAMP)
    RETURNING id_caja INTO caja_id;
    
    -- Retornar el mensaje de éxito
    RETURN 'Caja abierta correctamente con ID: ' || caja_id;
END;
$$;
 L   DROP FUNCTION public.abrir_caja(monto_inicial numeric, usuario_id integer);
       public          postgres    false    6                       1255    17636    actualizar_inventario()    FUNCTION     ~  CREATE FUNCTION public.actualizar_inventario() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Verificar si el producto ya está en el inventario
    IF EXISTS (SELECT 1 FROM inventario WHERE id_producto = NEW.id_producto) THEN
        -- Si el producto ya está, actualizar la cantidad
        UPDATE inventario 
        SET cantidad = cantidad + NEW.cantidad
        WHERE id_producto = NEW.id_producto;
    ELSE
        -- Si el producto no está, agregarlo con la cantidad inicial
        INSERT INTO inventario (id_producto, cantidad)
        VALUES (NEW.id_producto, NEW.cantidad);
    END IF;

    RETURN NEW;
END;
$$;
 .   DROP FUNCTION public.actualizar_inventario();
       public          postgres    false    6            +           1255    19053    cerrar_caja(numeric, integer)    FUNCTION     &  CREATE FUNCTION public.cerrar_caja(monto_final_param numeric, usuario_id integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    caja_id INTEGER;
BEGIN
    -- Buscar la caja abierta por este usuario
    SELECT id_caja INTO caja_id
    FROM cajas
    WHERE usuario = usuario_id AND estado = 'Abierta'
    ORDER BY fecha_apertura DESC
    LIMIT 1;
    
    -- Verificar que exista una caja abierta
    IF caja_id IS NULL THEN
        RETURN 'No hay caja abierta para este usuario.';
    END IF;

    -- Actualizar el monto final y el estado de la caja
    UPDATE cajas
    SET monto_final = monto_final_param, estado = 'Cerrada', fecha_cierre = CURRENT_TIMESTAMP
    WHERE id_caja = caja_id;

    -- Retornar mensaje de éxito
    RETURN 'Caja cerrada correctamente. Caja ID: ' || caja_id;
END;
$$;
 Q   DROP FUNCTION public.cerrar_caja(monto_final_param numeric, usuario_id integer);
       public          postgres    false    6                       1255    17651    fn_insertar_libro_compras()    FUNCTION     �  CREATE FUNCTION public.fn_insertar_libro_compras() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total numeric(10,2);
BEGIN
    -- Calcular el total sumando todos los detalles de la compra
    SELECT COALESCE(SUM(cantidad * precio_unitario), 0)
    INTO v_total
    FROM detalle_compras
    WHERE id_compra = NEW.id_compra;

    -- Imprimir el total calculado para depuración
    RAISE NOTICE 'Total Calculado para ID de Compra %: %', NEW.id_compra, v_total;

    -- Insertar en libro_compras
    INSERT INTO libro_compras (id_compra, fecha_registro, total)
    VALUES (NEW.id_compra, CURRENT_DATE, v_total);

    RETURN NEW;
END;
$$;
 2   DROP FUNCTION public.fn_insertar_libro_compras();
       public          postgres    false    6            ,           1255    19178    generar_cuentas_por_cobrar()    FUNCTION     ^  CREATE FUNCTION public.generar_cuentas_por_cobrar() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    monto_total DECIMAL(10, 2);
    monto_por_cuota DECIMAL(10, 2);
    fecha_vencimiento DATE;
    i INTEGER;
BEGIN
    -- Verificar si las cuotas son mayores a 1
    IF NEW.cuotas > 1 THEN
        -- Calcular el monto total con IVA
        SELECT SUM(
            dv.precio_unitario * dv.cantidad + 
            (dv.precio_unitario * dv.cantidad * p.tipo_iva::numeric / 100)
        )
        INTO monto_total
        FROM detalle_venta dv
        JOIN producto p ON dv.producto_id = p.id_producto
        WHERE dv.venta_id = NEW.id;

        -- Mostrar el valor de monto_total en los logs
        RAISE NOTICE 'Monto total calculado: %', monto_total;

        -- Verificar si el monto total es NULL
        IF monto_total IS NULL THEN
            RAISE EXCEPTION 'El monto total es NULL, no se puede continuar';
        END IF;

        -- Calcular el monto por cuota
        monto_por_cuota := monto_total / NEW.cuotas;

        -- Insertar las cuotas en la tabla cuentas_por_cobrar
        FOR i IN 1..NEW.cuotas LOOP
            -- Calcular la fecha de vencimiento (incrementando por meses)
            fecha_vencimiento := NEW.fecha + ((i - 1) * INTERVAL '1 month');
            
            INSERT INTO cuentas_por_cobrar (
                venta_id, numero_cuota, fecha_vencimiento, monto, estado
            ) VALUES (
                NEW.id, i, fecha_vencimiento, monto_por_cuota, 'pendiente'
            );
        END LOOP;
    END IF;

    RETURN NEW; -- Continuar con la inserción en la tabla ventas
END $$;
 3   DROP FUNCTION public.generar_cuentas_por_cobrar();
       public          postgres    false    6            -           1255    27402 �   generar_venta(integer, character varying, integer, jsonb, timestamp without time zone, character varying, integer, integer, numeric)    FUNCTION     �  CREATE FUNCTION public.generar_venta(p_cliente_id integer, p_forma_pago character varying, p_cuotas integer, p_detalles jsonb, p_fecha timestamp without time zone, p_metodo_pago character varying DEFAULT NULL::character varying, p_nota_credito_id integer DEFAULT NULL::integer, p_solicitud_id integer DEFAULT NULL::integer, p_monto_total_servicios numeric DEFAULT NULL::numeric) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_numero_factura INTEGER;
    v_timbrado VARCHAR(15);
    v_rango_inicio INTEGER;
    v_rango_fin INTEGER;
    v_id_rango INTEGER;
    v_fecha_inicio TIMESTAMP;
    v_fecha_fin TIMESTAMP;
    v_monto_total DECIMAL(10, 2);
    v_monto_por_cuota DECIMAL(10, 2);
    v_fecha_vencimiento DATE;
    v_monto_nc_aplicado DECIMAL(10, 2) := 0;
    i INTEGER;
    v_venta_id INTEGER; -- Variable para almacenar el ID de la venta
BEGIN
    -- Bloquear el rango de facturas activo para evitar conflictos
    SELECT id, rango_inicio, rango_fin, timbrado, actual, fecha_inicio, fecha_fin
    INTO v_id_rango, v_rango_inicio, v_rango_fin, v_timbrado, v_numero_factura, v_fecha_inicio, v_fecha_fin
    FROM rango_facturas
    WHERE activo = true FOR UPDATE;

    -- Verificar que existe un rango activo
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No hay un rango de facturas activo';
    END IF;

    -- Verificar que la fecha esté dentro del rango permitido
    IF p_fecha < v_fecha_inicio OR p_fecha > v_fecha_fin THEN
        RAISE EXCEPTION 'La fecha de la factura (%), no está dentro del rango válido (% - %)', p_fecha, v_fecha_inicio, v_fecha_fin;
    END IF;

    -- Verificar que el número de factura no haya superado el rango disponible
    IF v_numero_factura >= v_rango_fin THEN
        RAISE EXCEPTION 'El rango de facturas ha sido agotado';
    END IF;

    -- Asignar el siguiente número de factura y actualizar el rango
    v_numero_factura := v_numero_factura + 1;
    UPDATE rango_facturas SET actual = v_numero_factura WHERE id = v_id_rango;

    -- Calcular el monto total de la venta con IVA desde los detalles
    SELECT SUM(
        (detalle->>'cantidad')::INTEGER * (detalle->>'precio_unitario')::NUMERIC(10,2) + 
        ((detalle->>'cantidad')::INTEGER * (detalle->>'precio_unitario')::NUMERIC(10,2) * p.tipo_iva::NUMERIC / 100)
    ) INTO v_monto_total
    FROM jsonb_array_elements(p_detalles) AS detalle
    JOIN producto p ON (detalle->>'id_producto')::INTEGER = p.id_producto;

    IF v_monto_total IS NULL THEN
        RAISE EXCEPTION 'El monto total no puede ser calculado porque los detalles son inválidos';
    END IF;

    -- Si se ha proporcionado un monto total de servicios, sumarlo al total de la venta
        v_monto_total := v_monto_total + COALESCE(p_monto_total_servicios, 0);
    

    -- Si se ha proporcionado una nota de crédito, aplicar su monto
    IF p_nota_credito_id IS NOT NULL THEN
        SELECT monto INTO v_monto_nc_aplicado
        FROM notas_credito_debito
        WHERE id = p_nota_credito_id AND estado = 'pendiente';

        IF v_monto_nc_aplicado IS NULL THEN
            RAISE EXCEPTION 'La nota de crédito proporcionada no es válida o ya ha sido utilizada';
        END IF;

        -- Aplicar el monto de la nota de crédito al total de la venta
        v_monto_total := v_monto_total - v_monto_nc_aplicado;

        -- Actualizar el estado de la nota de crédito a "aplicada"
        UPDATE notas_credito_debito
        SET estado = 'aplicada', fecha_aplicacion = NOW(), venta_id = v_venta_id
        WHERE id = p_nota_credito_id;
    END IF;

    -- Insertar la cabecera de la venta incluyendo los campos solicitud_id y monto_total_servicios
    INSERT INTO ventas (
        cliente_id, fecha, forma_pago, estado, cuotas, numero_factura, timbrado, nota_credito_id, monto_nc_aplicado, metodo_pago, solicitud_id, monto_total_final
    )
    VALUES (
        p_cliente_id, p_fecha, p_forma_pago, 'pendiente', p_cuotas, v_numero_factura, v_timbrado, p_nota_credito_id, v_monto_nc_aplicado, p_metodo_pago, p_solicitud_id, v_monto_total
    )
    RETURNING id INTO v_venta_id;

    -- Insertar los detalles de la venta
    INSERT INTO detalle_venta (venta_id, producto_id, cantidad, precio_unitario)
    SELECT
        v_venta_id,
        (detalle->>'id_producto')::INTEGER,
        (detalle->>'cantidad')::INTEGER,
        (detalle->>'precio_unitario')::NUMERIC(10,2)
    FROM jsonb_array_elements(p_detalles) AS detalle;

    -- Si la venta es a cuotas, generar las cuentas por cobrar
    IF p_cuotas > 1 THEN
        v_monto_por_cuota := v_monto_total / p_cuotas;

        FOR i IN 1..p_cuotas LOOP
            v_fecha_vencimiento := p_fecha + ((i - 1) * INTERVAL '1 month');
            INSERT INTO cuentas_por_cobrar (
                venta_id, numero_cuota, fecha_vencimiento, monto, estado
            )
            VALUES (
                v_venta_id, i, v_fecha_vencimiento, v_monto_por_cuota, 'pendiente'
            );
        END LOOP;
    END IF;

    -- Si se ha proporcionado una solicitud_id, actualizar su estado a "facturado"
    IF p_solicitud_id IS NOT NULL THEN
        UPDATE servicios_cabecera
        SET estado = 'facturado'
        WHERE id_cabecera = p_solicitud_id;
    END IF;

    -- Retornar el ID de la venta generada
    RETURN v_venta_id;
END;
$$;
   DROP FUNCTION public.generar_venta(p_cliente_id integer, p_forma_pago character varying, p_cuotas integer, p_detalles jsonb, p_fecha timestamp without time zone, p_metodo_pago character varying, p_nota_credito_id integer, p_solicitud_id integer, p_monto_total_servicios numeric);
       public          postgres    false    6            )           1255    19137 o   insertar_cliente(character varying, character varying, character varying, character varying, character varying)    FUNCTION     �  CREATE FUNCTION public.insertar_cliente(p_nombre character varying, p_apellido character varying, p_direccion character varying, p_telefono character varying, p_ruc_ci character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    nuevo_id INTEGER;
BEGIN
    INSERT INTO clientes (nombre, apellido, direccion, telefono, ruc_ci)
    VALUES (p_nombre, p_apellido, p_direccion, p_telefono, p_ruc_ci)
    RETURNING id_cliente INTO nuevo_id;

    RETURN nuevo_id;
END;
$$;
 �   DROP FUNCTION public.insertar_cliente(p_nombre character varying, p_apellido character varying, p_direccion character varying, p_telefono character varying, p_ruc_ci character varying);
       public          postgres    false    6            *           1255    19142    insertar_en_libro_ventas()    FUNCTION     [  CREATE FUNCTION public.insertar_en_libro_ventas() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO libro_ventas (
        numero_factura, timbrado, cliente_id, cliente_nombre, fecha, forma_pago, monto_total, estado
    ) VALUES (
        NEW.numero_factura,
        NEW.timbrado,
        NEW.cliente_id,
        (SELECT c.nombre FROM clientes c WHERE c.id_cliente = NEW.cliente_id),
        NEW.fecha,
        NEW.forma_pago,
        (SELECT SUM(dv.precio_unitario * dv.cantidad) FROM detalle_venta dv WHERE dv.venta_id = NEW.id),
        NEW.estado
    );

    RETURN NEW;
END;
$$;
 1   DROP FUNCTION public.insertar_en_libro_ventas();
       public          postgres    false    6            .           1255    19184 9   registrar_pago(integer, numeric, date, character varying)    FUNCTION     �  CREATE FUNCTION public.registrar_pago(p_cuenta_id integer, p_monto_pago numeric, p_fecha_pago date, p_forma_pago character varying) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
    saldo_pendiente NUMERIC;
    estado_pago VARCHAR;
BEGIN
    -- Obtener el saldo pendiente de la cuenta
    SELECT monto - COALESCE(monto_pagado, 0) INTO saldo_pendiente
    FROM public.cuentas_por_cobrar
    WHERE id = p_cuenta_id;

    -- Verificar si el monto del pago es mayor que el saldo pendiente
    IF p_monto_pago > saldo_pendiente THEN
        RETURN json_build_object('error', 'El monto del pago excede el saldo pendiente');
    END IF;

    -- Determinar el estado del pago (completo o parcial)
    IF p_monto_pago >= saldo_pendiente THEN
        estado_pago := 'completo';
    ELSE
        estado_pago := 'parcial';
    END IF;

    -- Registrar el pago en la tabla pagos
    INSERT INTO public.pagos (cuenta_id, monto_pago, fecha_pago, forma_pago, estado_pago)
    VALUES (p_cuenta_id, p_monto_pago, p_fecha_pago, p_forma_pago, estado_pago);

    -- Actualizar la cuenta por cobrar con el monto pagado
    UPDATE public.cuentas_por_cobrar
    SET monto_pagado = COALESCE(monto_pagado, 0) + p_monto_pago,
        estado = CASE 
                    WHEN monto_pagado + p_monto_pago >= monto THEN 'pagada'
                    ELSE 'pendiente'
                 END
    WHERE id = p_cuenta_id;

    -- Devolver un mensaje de éxito
    RETURN json_build_object('message', 'Pago registrado correctamente');
END;
$$;
 �   DROP FUNCTION public.registrar_pago(p_cuenta_id integer, p_monto_pago numeric, p_fecha_pago date, p_forma_pago character varying);
       public          postgres    false    6            �            1259    17664    ajustes_inventario    TABLE     �   CREATE TABLE public.ajustes_inventario (
    id_ajuste integer NOT NULL,
    id_producto integer NOT NULL,
    cantidad_ajustada integer NOT NULL,
    fecha_ajuste date NOT NULL,
    motivo_ajuste character varying(255)
);
 &   DROP TABLE public.ajustes_inventario;
       public            postgres    false    6            �            1259    17662     ajustes_inventario_id_ajuste_seq    SEQUENCE     �   CREATE SEQUENCE public.ajustes_inventario_id_ajuste_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 7   DROP SEQUENCE public.ajustes_inventario_id_ajuste_seq;
       public          postgres    false    6    228            4           0    0     ajustes_inventario_id_ajuste_seq    SEQUENCE OWNED BY     e   ALTER SEQUENCE public.ajustes_inventario_id_ajuste_seq OWNED BY public.ajustes_inventario.id_ajuste;
          public          postgres    false    227            �            1259    17381    aperturas_de_caja    TABLE     #  CREATE TABLE public.aperturas_de_caja (
    id_apertura_cierre_caja integer NOT NULL,
    numero_caja integer NOT NULL,
    nombre_usuario character varying(50) NOT NULL,
    estado character varying(10) NOT NULL,
    fecha_apertura date NOT NULL,
    hora_apertura time without time zone NOT NULL,
    fecha_cierre date,
    hora_cierre time without time zone,
    monto_inicial integer,
    CONSTRAINT aperturas_de_caja_estado_check CHECK (((estado)::text = ANY ((ARRAY['Abierto'::character varying, 'Cerrado'::character varying])::text[])))
);
 %   DROP TABLE public.aperturas_de_caja;
       public            postgres    false    6            �            1259    17379 -   aperturas_de_caja_id_apertura_cierre_caja_seq    SEQUENCE     �   CREATE SEQUENCE public.aperturas_de_caja_id_apertura_cierre_caja_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 D   DROP SEQUENCE public.aperturas_de_caja_id_apertura_cierre_caja_seq;
       public          postgres    false    6    207            5           0    0 -   aperturas_de_caja_id_apertura_cierre_caja_seq    SEQUENCE OWNED BY        ALTER SEQUENCE public.aperturas_de_caja_id_apertura_cierre_caja_seq OWNED BY public.aperturas_de_caja.id_apertura_cierre_caja;
          public          postgres    false    206            �            1259    17471    cabecera_pedido_interno    TABLE       CREATE TABLE public.cabecera_pedido_interno (
    numero_pedido integer NOT NULL,
    departamento_solicitante character varying(100) NOT NULL,
    telefono character varying(20),
    correo character varying(100),
    fecha_pedido date NOT NULL,
    fecha_entrega_solicitada date
);
 +   DROP TABLE public.cabecera_pedido_interno;
       public            postgres    false    6            �            1259    19037    cajas    TABLE     �  CREATE TABLE public.cajas (
    id_caja integer NOT NULL,
    fecha_apertura date NOT NULL,
    hora_apertura time without time zone NOT NULL,
    monto_inicial numeric(10,2) NOT NULL,
    fecha_cierre date,
    hora_cierre time without time zone,
    monto_final numeric(10,2),
    estado character varying(10) NOT NULL,
    usuario integer NOT NULL,
    CONSTRAINT caja_estado_check CHECK (((estado)::text = ANY ((ARRAY['Abierta'::character varying, 'Cerrada'::character varying])::text[])))
);
    DROP TABLE public.cajas;
       public            postgres    false    6            �            1259    19035    caja_id_caja_seq    SEQUENCE     �   CREATE SEQUENCE public.caja_id_caja_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 '   DROP SEQUENCE public.caja_id_caja_seq;
       public          postgres    false    6    241            6           0    0    caja_id_caja_seq    SEQUENCE OWNED BY     F   ALTER SEQUENCE public.caja_id_caja_seq OWNED BY public.cajas.id_caja;
          public          postgres    false    240            �            1259    17239    ciudades    TABLE     m   CREATE TABLE public.ciudades (
    id_ciudad integer NOT NULL,
    nombre character varying(255) NOT NULL
);
    DROP TABLE public.ciudades;
       public            postgres    false    6            �            1259    17237    ciudades_id_seq    SEQUENCE     �   CREATE SEQUENCE public.ciudades_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 &   DROP SEQUENCE public.ciudades_id_seq;
       public          postgres    false    201    6            7           0    0    ciudades_id_seq    SEQUENCE OWNED BY     J   ALTER SEQUENCE public.ciudades_id_seq OWNED BY public.ciudades.id_ciudad;
          public          postgres    false    200            �            1259    17395    clientes    TABLE       CREATE TABLE public.clientes (
    id_cliente integer NOT NULL,
    nombre character varying(50) NOT NULL,
    apellido character varying(50) NOT NULL,
    direccion character varying(100),
    telefono character varying(20),
    ruc_ci character varying(15)
);
    DROP TABLE public.clientes;
       public            postgres    false    6            �            1259    17393    clientes_id_cliente_seq    SEQUENCE     �   CREATE SEQUENCE public.clientes_id_cliente_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 .   DROP SEQUENCE public.clientes_id_cliente_seq;
       public          postgres    false    6    209            8           0    0    clientes_id_cliente_seq    SEQUENCE OWNED BY     S   ALTER SEQUENCE public.clientes_id_cliente_seq OWNED BY public.clientes.id_cliente;
          public          postgres    false    208            �            1259    17596    compras    TABLE     -  CREATE TABLE public.compras (
    id_compra integer NOT NULL,
    numero_factura character varying(50) NOT NULL,
    fecha_factura date NOT NULL,
    id_proveedor integer NOT NULL,
    id_orden_compra integer NOT NULL,
    condicion_pago character varying(20) NOT NULL,
    cantidad_cuotas integer
);
    DROP TABLE public.compras;
       public            postgres    false    6            �            1259    17594    compras_id_compra_seq    SEQUENCE     �   CREATE SEQUENCE public.compras_id_compra_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 ,   DROP SEQUENCE public.compras_id_compra_seq;
       public          postgres    false    6    221            9           0    0    compras_id_compra_seq    SEQUENCE OWNED BY     O   ALTER SEQUENCE public.compras_id_compra_seq OWNED BY public.compras.id_compra;
          public          postgres    false    220            �            1259    19167    cuentas_por_cobrar    TABLE       CREATE TABLE public.cuentas_por_cobrar (
    id integer NOT NULL,
    venta_id integer NOT NULL,
    numero_cuota integer NOT NULL,
    fecha_vencimiento date NOT NULL,
    monto numeric(10,2) NOT NULL,
    estado character varying(20) NOT NULL,
    fecha_pago date
);
 &   DROP TABLE public.cuentas_por_cobrar;
       public            postgres    false    6            �            1259    19165    cuentas_por_cobrar_id_seq    SEQUENCE     �   CREATE SEQUENCE public.cuentas_por_cobrar_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 0   DROP SEQUENCE public.cuentas_por_cobrar_id_seq;
       public          postgres    false    251    6            :           0    0    cuentas_por_cobrar_id_seq    SEQUENCE OWNED BY     W   ALTER SEQUENCE public.cuentas_por_cobrar_id_seq OWNED BY public.cuentas_por_cobrar.id;
          public          postgres    false    250                       1259    20254 
   descuentos    TABLE     M  CREATE TABLE public.descuentos (
    id_descuento integer NOT NULL,
    nombre character varying(100) NOT NULL,
    porcentaje numeric(5,2),
    estado character varying(20) DEFAULT 'inactivo'::character varying,
    CONSTRAINT descuentos_porcentaje_check CHECK (((porcentaje >= (0)::numeric) AND (porcentaje <= (100)::numeric)))
);
    DROP TABLE public.descuentos;
       public            postgres    false    6                       1259    20252    descuentos_id_descuento_seq    SEQUENCE     �   CREATE SEQUENCE public.descuentos_id_descuento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 2   DROP SEQUENCE public.descuentos_id_descuento_seq;
       public          postgres    false    6    271            ;           0    0    descuentos_id_descuento_seq    SEQUENCE OWNED BY     [   ALTER SEQUENCE public.descuentos_id_descuento_seq OWNED BY public.descuentos.id_descuento;
          public          postgres    false    270            �            1259    17614    detalle_compras    TABLE       CREATE TABLE public.detalle_compras (
    id_detalle_compra integer NOT NULL,
    id_compra integer NOT NULL,
    id_producto integer NOT NULL,
    descripcion character varying(255) NOT NULL,
    cantidad integer NOT NULL,
    precio_unitario numeric(10,2) NOT NULL
);
 #   DROP TABLE public.detalle_compras;
       public            postgres    false    6            �            1259    17612 %   detalle_compras_id_detalle_compra_seq    SEQUENCE     �   CREATE SEQUENCE public.detalle_compras_id_detalle_compra_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 <   DROP SEQUENCE public.detalle_compras_id_detalle_compra_seq;
       public          postgres    false    6    223            <           0    0 %   detalle_compras_id_detalle_compra_seq    SEQUENCE OWNED BY     o   ALTER SEQUENCE public.detalle_compras_id_detalle_compra_seq OWNED BY public.detalle_compras.id_detalle_compra;
          public          postgres    false    222                       1259    20178    detalle_notas_credito_debito    TABLE     �   CREATE TABLE public.detalle_notas_credito_debito (
    id integer NOT NULL,
    nota_id integer,
    producto_id integer,
    cantidad numeric(10,2),
    precio_unitario numeric(10,2),
    monto numeric(10,2)
);
 0   DROP TABLE public.detalle_notas_credito_debito;
       public            postgres    false    6                       1259    20176 #   detalle_notas_credito_debito_id_seq    SEQUENCE     �   CREATE SEQUENCE public.detalle_notas_credito_debito_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 :   DROP SEQUENCE public.detalle_notas_credito_debito_id_seq;
       public          postgres    false    6    263            =           0    0 #   detalle_notas_credito_debito_id_seq    SEQUENCE OWNED BY     k   ALTER SEQUENCE public.detalle_notas_credito_debito_id_seq OWNED BY public.detalle_notas_credito_debito.id;
          public          postgres    false    262            �            1259    17578    detalle_orden_compra    TABLE       CREATE TABLE public.detalle_orden_compra (
    id_detalle integer NOT NULL,
    id_orden_compra integer NOT NULL,
    id_producto integer NOT NULL,
    descripcion character varying(255) NOT NULL,
    cantidad integer NOT NULL,
    precio_unitario numeric(10,2) NOT NULL
);
 (   DROP TABLE public.detalle_orden_compra;
       public            postgres    false    6            �            1259    17576 #   detalle_orden_compra_id_detalle_seq    SEQUENCE     �   CREATE SEQUENCE public.detalle_orden_compra_id_detalle_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 :   DROP SEQUENCE public.detalle_orden_compra_id_detalle_seq;
       public          postgres    false    6    219            >           0    0 #   detalle_orden_compra_id_detalle_seq    SEQUENCE OWNED BY     k   ALTER SEQUENCE public.detalle_orden_compra_id_detalle_seq OWNED BY public.detalle_orden_compra.id_detalle;
          public          postgres    false    218            �            1259    17478    detalle_pedido_interno    TABLE     �   CREATE TABLE public.detalle_pedido_interno (
    id integer NOT NULL,
    numero_pedido integer,
    id_producto integer NOT NULL,
    nombre_producto character varying(100) NOT NULL,
    cantidad integer NOT NULL
);
 *   DROP TABLE public.detalle_pedido_interno;
       public            postgres    false    6            �            1259    17476    detalle_pedido_interno_id_seq    SEQUENCE     �   CREATE SEQUENCE public.detalle_pedido_interno_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 4   DROP SEQUENCE public.detalle_pedido_interno_id_seq;
       public          postgres    false    6    215            ?           0    0    detalle_pedido_interno_id_seq    SEQUENCE OWNED BY     _   ALTER SEQUENCE public.detalle_pedido_interno_id_seq OWNED BY public.detalle_pedido_interno.id;
          public          postgres    false    214            �            1259    19121    detalle_venta    TABLE     �   CREATE TABLE public.detalle_venta (
    id integer NOT NULL,
    venta_id integer,
    producto_id integer,
    cantidad integer,
    precio_unitario numeric(10,2)
);
 !   DROP TABLE public.detalle_venta;
       public            postgres    false    6            �            1259    19119    detalle_venta_id_seq    SEQUENCE     �   CREATE SEQUENCE public.detalle_venta_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 +   DROP SEQUENCE public.detalle_venta_id_seq;
       public          postgres    false    247    6            @           0    0    detalle_venta_id_seq    SEQUENCE OWNED BY     M   ALTER SEQUENCE public.detalle_venta_id_seq OWNED BY public.detalle_venta.id;
          public          postgres    false    246            �            1259    17457    entrega_cheques    TABLE        CREATE TABLE public.entrega_cheques (
    id_entrega integer NOT NULL,
    id_proveedor integer NOT NULL,
    monto numeric(10,2) NOT NULL,
    fecha_entrega date NOT NULL,
    numero_cheque character varying(20) NOT NULL,
    descripcion text NOT NULL
);
 #   DROP TABLE public.entrega_cheques;
       public            postgres    false    6            �            1259    17455    entrega_cheques_id_entrega_seq    SEQUENCE     �   CREATE SEQUENCE public.entrega_cheques_id_entrega_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 5   DROP SEQUENCE public.entrega_cheques_id_entrega_seq;
       public          postgres    false    212    6            A           0    0    entrega_cheques_id_entrega_seq    SEQUENCE OWNED BY     a   ALTER SEQUENCE public.entrega_cheques_id_entrega_seq OWNED BY public.entrega_cheques.id_entrega;
          public          postgres    false    211            �            1259    17630 
   inventario    TABLE     n   CREATE TABLE public.inventario (
    id_producto integer NOT NULL,
    cantidad integer DEFAULT 0 NOT NULL
);
    DROP TABLE public.inventario;
       public            postgres    false    6            �            1259    17640    libro_compras    TABLE     �   CREATE TABLE public.libro_compras (
    id_libro_compra integer NOT NULL,
    id_compra integer NOT NULL,
    fecha_registro date NOT NULL,
    total numeric(10,2) NOT NULL
);
 !   DROP TABLE public.libro_compras;
       public            postgres    false    6            �            1259    17638 !   libro_compras_id_libro_compra_seq    SEQUENCE     �   CREATE SEQUENCE public.libro_compras_id_libro_compra_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 8   DROP SEQUENCE public.libro_compras_id_libro_compra_seq;
       public          postgres    false    6    226            B           0    0 !   libro_compras_id_libro_compra_seq    SEQUENCE OWNED BY     g   ALTER SEQUENCE public.libro_compras_id_libro_compra_seq OWNED BY public.libro_compras.id_libro_compra;
          public          postgres    false    225            �            1259    19146    libro_ventas    TABLE     �  CREATE TABLE public.libro_ventas (
    id integer NOT NULL,
    numero_factura character varying NOT NULL,
    timbrado character varying(15) NOT NULL,
    cliente_id integer NOT NULL,
    cliente_nombre character varying(255),
    fecha date NOT NULL,
    forma_pago character varying(50),
    monto_total numeric(15,2),
    estado character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
     DROP TABLE public.libro_ventas;
       public            postgres    false    6            �            1259    19144    libro_ventas_id_seq    SEQUENCE     �   CREATE SEQUENCE public.libro_ventas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 *   DROP SEQUENCE public.libro_ventas_id_seq;
       public          postgres    false    249    6            C           0    0    libro_ventas_id_seq    SEQUENCE OWNED BY     K   ALTER SEQUENCE public.libro_ventas_id_seq OWNED BY public.libro_ventas.id;
          public          postgres    false    248            �            1259    17707    nota_remision    TABLE     ,  CREATE TABLE public.nota_remision (
    id_nota_remision integer NOT NULL,
    numero_remision character varying(50) NOT NULL,
    fecha_remision date NOT NULL,
    id_proveedor integer NOT NULL,
    id_compra integer NOT NULL,
    estado character varying(20) DEFAULT 'Activo'::character varying
);
 !   DROP TABLE public.nota_remision;
       public            postgres    false    6            �            1259    20065    nota_remision_cabecera    TABLE     #  CREATE TABLE public.nota_remision_cabecera (
    id_remision integer NOT NULL,
    cliente_id integer NOT NULL,
    fecha timestamp without time zone DEFAULT now(),
    estado character varying(50) DEFAULT 'pendiente'::character varying,
    numero_factura character varying(50) NOT NULL
);
 *   DROP TABLE public.nota_remision_cabecera;
       public            postgres    false    6            �            1259    20063 &   nota_remision_cabecera_id_remision_seq    SEQUENCE     �   CREATE SEQUENCE public.nota_remision_cabecera_id_remision_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 =   DROP SEQUENCE public.nota_remision_cabecera_id_remision_seq;
       public          postgres    false    255    6            D           0    0 &   nota_remision_cabecera_id_remision_seq    SEQUENCE OWNED BY     q   ALTER SEQUENCE public.nota_remision_cabecera_id_remision_seq OWNED BY public.nota_remision_cabecera.id_remision;
          public          postgres    false    254            �            1259    17739    nota_remision_detalle    TABLE       CREATE TABLE public.nota_remision_detalle (
    id_detalle integer NOT NULL,
    id_nota_remision integer NOT NULL,
    id_producto integer NOT NULL,
    nombre_producto character varying(100) NOT NULL,
    cantidad numeric(10,2) NOT NULL,
    precio_unitario numeric(10,2) NOT NULL
);
 )   DROP TABLE public.nota_remision_detalle;
       public            postgres    false    6            �            1259    17737 $   nota_remision_detalle_id_detalle_seq    SEQUENCE     �   CREATE SEQUENCE public.nota_remision_detalle_id_detalle_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 ;   DROP SEQUENCE public.nota_remision_detalle_id_detalle_seq;
       public          postgres    false    234    6            E           0    0 $   nota_remision_detalle_id_detalle_seq    SEQUENCE OWNED BY     m   ALTER SEQUENCE public.nota_remision_detalle_id_detalle_seq OWNED BY public.nota_remision_detalle.id_detalle;
          public          postgres    false    233            �            1259    17705 "   nota_remision_id_nota_remision_seq    SEQUENCE     �   CREATE SEQUENCE public.nota_remision_id_nota_remision_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 9   DROP SEQUENCE public.nota_remision_id_nota_remision_seq;
       public          postgres    false    232    6            F           0    0 "   nota_remision_id_nota_remision_seq    SEQUENCE OWNED BY     i   ALTER SEQUENCE public.nota_remision_id_nota_remision_seq OWNED BY public.nota_remision.id_nota_remision;
          public          postgres    false    231                       1259    20080    nota_remision_venta_cabecera    TABLE     )  CREATE TABLE public.nota_remision_venta_cabecera (
    id_remision integer NOT NULL,
    cliente_id integer NOT NULL,
    fecha timestamp without time zone DEFAULT now(),
    estado character varying(50) DEFAULT 'pendiente'::character varying,
    numero_factura character varying(50) NOT NULL
);
 0   DROP TABLE public.nota_remision_venta_cabecera;
       public            postgres    false    6                        1259    20078 ,   nota_remision_venta_cabecera_id_remision_seq    SEQUENCE     �   CREATE SEQUENCE public.nota_remision_venta_cabecera_id_remision_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 C   DROP SEQUENCE public.nota_remision_venta_cabecera_id_remision_seq;
       public          postgres    false    257    6            G           0    0 ,   nota_remision_venta_cabecera_id_remision_seq    SEQUENCE OWNED BY     }   ALTER SEQUENCE public.nota_remision_venta_cabecera_id_remision_seq OWNED BY public.nota_remision_venta_cabecera.id_remision;
          public          postgres    false    256                       1259    20095    nota_remision_venta_detalle    TABLE     �   CREATE TABLE public.nota_remision_venta_detalle (
    id integer NOT NULL,
    remision_id integer NOT NULL,
    producto_id integer NOT NULL,
    cantidad integer NOT NULL,
    precio_unitario numeric(10,2) NOT NULL
);
 /   DROP TABLE public.nota_remision_venta_detalle;
       public            postgres    false    6                       1259    20093 "   nota_remision_venta_detalle_id_seq    SEQUENCE     �   CREATE SEQUENCE public.nota_remision_venta_detalle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 9   DROP SEQUENCE public.nota_remision_venta_detalle_id_seq;
       public          postgres    false    6    259            H           0    0 "   nota_remision_venta_detalle_id_seq    SEQUENCE OWNED BY     i   ALTER SEQUENCE public.nota_remision_venta_detalle_id_seq OWNED BY public.nota_remision_venta_detalle.id;
          public          postgres    false    258            �            1259    17678    notas    TABLE     �  CREATE TABLE public.notas (
    id_nota integer NOT NULL,
    tipo_nota character varying(10) NOT NULL,
    numero_nota character varying(50) NOT NULL,
    fecha_nota date NOT NULL,
    id_proveedor integer NOT NULL,
    id_compra integer NOT NULL,
    monto numeric(10,2) NOT NULL,
    descripcion text,
    estado character varying(20) DEFAULT 'Activo'::character varying NOT NULL
);
    DROP TABLE public.notas;
       public            postgres    false    6                       1259    20152    notas_credito_debito    TABLE     �  CREATE TABLE public.notas_credito_debito (
    id integer NOT NULL,
    cliente_id integer,
    tipo character varying(20) NOT NULL,
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    estado character varying(50) DEFAULT 'pendiente'::character varying,
    monto numeric(10,2) NOT NULL,
    motivo text,
    venta_id integer,
    fecha_aplicacion timestamp without time zone
);
 (   DROP TABLE public.notas_credito_debito;
       public            postgres    false    6                       1259    20150    notas_credito_debito_id_seq    SEQUENCE     �   CREATE SEQUENCE public.notas_credito_debito_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 2   DROP SEQUENCE public.notas_credito_debito_id_seq;
       public          postgres    false    6    261            I           0    0    notas_credito_debito_id_seq    SEQUENCE OWNED BY     [   ALTER SEQUENCE public.notas_credito_debito_id_seq OWNED BY public.notas_credito_debito.id;
          public          postgres    false    260            �            1259    17676    notas_id_nota_seq    SEQUENCE     �   CREATE SEQUENCE public.notas_id_nota_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 (   DROP SEQUENCE public.notas_id_nota_seq;
       public          postgres    false    6    230            J           0    0    notas_id_nota_seq    SEQUENCE OWNED BY     G   ALTER SEQUENCE public.notas_id_nota_seq OWNED BY public.notas.id_nota;
          public          postgres    false    229                       1259    20448    orden_servicio    TABLE     8  CREATE TABLE public.orden_servicio (
    id_orden integer NOT NULL,
    id_solicitud integer NOT NULL,
    id_trabajador integer NOT NULL,
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    estado character varying(20) DEFAULT 'pendiente'::character varying,
    observaciones text
);
 "   DROP TABLE public.orden_servicio;
       public            postgres    false    6                       1259    20446    orden_servicio_id_orden_seq    SEQUENCE     �   CREATE SEQUENCE public.orden_servicio_id_orden_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 2   DROP SEQUENCE public.orden_servicio_id_orden_seq;
       public          postgres    false    6    281            K           0    0    orden_servicio_id_orden_seq    SEQUENCE OWNED BY     [   ALTER SEQUENCE public.orden_servicio_id_orden_seq OWNED BY public.orden_servicio.id_orden;
          public          postgres    false    280            �            1259    17534    ordenes_compra    TABLE     s  CREATE TABLE public.ordenes_compra (
    id_orden_compra integer NOT NULL,
    fecha_emision date NOT NULL,
    fecha_entrega date,
    condiciones_entrega character varying(255),
    metodo_pago character varying(50) NOT NULL,
    cuotas integer,
    estado_orden character varying(50) NOT NULL,
    id_proveedor integer NOT NULL,
    id_presupuesto integer NOT NULL
);
 "   DROP TABLE public.ordenes_compra;
       public            postgres    false    6            �            1259    17532 "   ordenes_compra_id_orden_compra_seq    SEQUENCE     �   CREATE SEQUENCE public.ordenes_compra_id_orden_compra_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 9   DROP SEQUENCE public.ordenes_compra_id_orden_compra_seq;
       public          postgres    false    217    6            L           0    0 "   ordenes_compra_id_orden_compra_seq    SEQUENCE OWNED BY     i   ALTER SEQUENCE public.ordenes_compra_id_orden_compra_seq OWNED BY public.ordenes_compra.id_orden_compra;
          public          postgres    false    216            �            1259    19187    pagos    TABLE     �   CREATE TABLE public.pagos (
    id integer NOT NULL,
    cuenta_id integer NOT NULL,
    monto_pago numeric(10,2) NOT NULL,
    fecha_pago date NOT NULL,
    forma_pago character varying(20) NOT NULL,
    estado_pago character varying(20) NOT NULL
);
    DROP TABLE public.pagos;
       public            postgres    false    6            �            1259    19185    pagos_id_seq    SEQUENCE     �   CREATE SEQUENCE public.pagos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 #   DROP SEQUENCE public.pagos_id_seq;
       public          postgres    false    6    253            M           0    0    pagos_id_seq    SEQUENCE OWNED BY     =   ALTER SEQUENCE public.pagos_id_seq OWNED BY public.pagos.id;
          public          postgres    false    252            �            1259    17231    paises    TABLE     �   CREATE TABLE public.paises (
    id_pais integer NOT NULL,
    nombre character varying(255) NOT NULL,
    gentilicio character varying(100) NOT NULL
);
    DROP TABLE public.paises;
       public            postgres    false    6            �            1259    17229    paises_id_seq    SEQUENCE     �   CREATE SEQUENCE public.paises_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE public.paises_id_seq;
       public          postgres    false    6    199            N           0    0    paises_id_seq    SEQUENCE OWNED BY     D   ALTER SEQUENCE public.paises_id_seq OWNED BY public.paises.id_pais;
          public          postgres    false    198                       1259    20391 -   presupuesto_cabecera_servicio_id_cabecera_seq    SEQUENCE     �   CREATE SEQUENCE public.presupuesto_cabecera_servicio_id_cabecera_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 D   DROP SEQUENCE public.presupuesto_cabecera_servicio_id_cabecera_seq;
       public          postgres    false    6                       1259    20393    presupuesto_cabecera_servicio    TABLE     i  CREATE TABLE public.presupuesto_cabecera_servicio (
    id_cabecera integer DEFAULT nextval('public.presupuesto_cabecera_servicio_id_cabecera_seq'::regclass) NOT NULL,
    id_cliente integer NOT NULL,
    fecha date NOT NULL,
    estado character varying(20) DEFAULT 'pendiente'::character varying,
    descuento numeric(10,2),
    monto_total numeric(10,2)
);
 1   DROP TABLE public.presupuesto_cabecera_servicio;
       public            postgres    false    274    6            �            1259    17439    presupuesto_detalle    TABLE     �   CREATE TABLE public.presupuesto_detalle (
    id_presupuesto integer,
    id_producto integer,
    cantidad integer,
    precio_unitario numeric(10,2),
    precio_total numeric(10,2),
    id_presupuesto_detalle integer NOT NULL
);
 '   DROP TABLE public.presupuesto_detalle;
       public            postgres    false    6            �            1259    18059 .   presupuesto_detalle_id_presupuesto_detalle_seq    SEQUENCE     �   CREATE SEQUENCE public.presupuesto_detalle_id_presupuesto_detalle_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 E   DROP SEQUENCE public.presupuesto_detalle_id_presupuesto_detalle_seq;
       public          postgres    false    6    210            O           0    0 .   presupuesto_detalle_id_presupuesto_detalle_seq    SEQUENCE OWNED BY     �   ALTER SEQUENCE public.presupuesto_detalle_id_presupuesto_detalle_seq OWNED BY public.presupuesto_detalle.id_presupuesto_detalle;
          public          postgres    false    235                       1259    20405 +   presupuesto_detalle_servicio_id_detalle_seq    SEQUENCE     �   CREATE SEQUENCE public.presupuesto_detalle_servicio_id_detalle_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 B   DROP SEQUENCE public.presupuesto_detalle_servicio_id_detalle_seq;
       public          postgres    false    6                       1259    20407    presupuesto_detalle_servicio    TABLE     @  CREATE TABLE public.presupuesto_detalle_servicio (
    id_detalle integer DEFAULT nextval('public.presupuesto_detalle_servicio_id_detalle_seq'::regclass) NOT NULL,
    id_cabecera integer NOT NULL,
    id_servicio integer,
    id_promocion integer,
    costo_servicio numeric(10,2),
    costo_promocion numeric(10,2)
);
 0   DROP TABLE public.presupuesto_detalle_servicio;
       public            postgres    false    276    6            �            1259    17342    presupuestos    TABLE     �   CREATE TABLE public.presupuestos (
    id_presupuesto integer NOT NULL,
    id_proveedor integer,
    fecharegistro date NOT NULL,
    fechavencimiento date NOT NULL,
    estado character varying(20)
);
     DROP TABLE public.presupuestos;
       public            postgres    false    6            �            1259    17340    presupuestos_id_presupuesto_seq    SEQUENCE     �   CREATE SEQUENCE public.presupuestos_id_presupuesto_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 6   DROP SEQUENCE public.presupuestos_id_presupuesto_seq;
       public          postgres    false    205    6            P           0    0    presupuestos_id_presupuesto_seq    SEQUENCE OWNED BY     c   ALTER SEQUENCE public.presupuestos_id_presupuesto_seq OWNED BY public.presupuestos.id_presupuesto;
          public          postgres    false    204            �            1259    17257    producto    TABLE     �  CREATE TABLE public.producto (
    id_producto integer NOT NULL,
    nombre character varying(255) NOT NULL,
    precio_unitario numeric(10,2) NOT NULL,
    precio_compra numeric(10,2) NOT NULL,
    estado character varying(20) DEFAULT 'Activo'::character varying,
    tipo_iva character varying(255),
    medida character varying(255),
    color character varying(255),
    material character varying(255),
    hilos character varying(255),
    categoria character varying(255)
);
    DROP TABLE public.producto;
       public            postgres    false    6            �            1259    17255    producto_id_producto_seq    SEQUENCE     �   CREATE SEQUENCE public.producto_id_producto_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 /   DROP SEQUENCE public.producto_id_producto_seq;
       public          postgres    false    203    6            Q           0    0    producto_id_producto_seq    SEQUENCE OWNED BY     U   ALTER SEQUENCE public.producto_id_producto_seq OWNED BY public.producto.id_producto;
          public          postgres    false    202                       1259    20244    promociones    TABLE     �   CREATE TABLE public.promociones (
    id_promocion integer NOT NULL,
    nombre character varying(100) NOT NULL,
    precio numeric(10,2) NOT NULL,
    estado character varying(20) DEFAULT 'inactivo'::character varying
);
    DROP TABLE public.promociones;
       public            postgres    false    6                       1259    20242    promociones_id_promocion_seq    SEQUENCE     �   CREATE SEQUENCE public.promociones_id_promocion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 3   DROP SEQUENCE public.promociones_id_promocion_seq;
       public          postgres    false    6    269            R           0    0    promociones_id_promocion_seq    SEQUENCE OWNED BY     ]   ALTER SEQUENCE public.promociones_id_promocion_seq OWNED BY public.promociones.id_promocion;
          public          postgres    false    268            �            1259    17220    proveedores    TABLE     N  CREATE TABLE public.proveedores (
    id_proveedor integer NOT NULL,
    nombre character varying(255) NOT NULL,
    direccion character varying(255) NOT NULL,
    telefono character varying(15) NOT NULL,
    email character varying(100) NOT NULL,
    ruc character varying(15) NOT NULL,
    id_pais integer,
    id_ciudad integer
);
    DROP TABLE public.proveedores;
       public            postgres    false    6            �            1259    17218    proveedores_id_seq    SEQUENCE     �   CREATE SEQUENCE public.proveedores_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 )   DROP SEQUENCE public.proveedores_id_seq;
       public          postgres    false    197    6            S           0    0    proveedores_id_seq    SEQUENCE OWNED BY     S   ALTER SEQUENCE public.proveedores_id_seq OWNED BY public.proveedores.id_proveedor;
          public          postgres    false    196            �            1259    19059    rango_facturas    TABLE     d  CREATE TABLE public.rango_facturas (
    id integer NOT NULL,
    timbrado character varying(15) NOT NULL,
    rango_inicio integer NOT NULL,
    rango_fin integer NOT NULL,
    actual integer DEFAULT 0 NOT NULL,
    fecha_inicio timestamp without time zone NOT NULL,
    fecha_fin timestamp without time zone NOT NULL,
    activo boolean DEFAULT false
);
 "   DROP TABLE public.rango_facturas;
       public            postgres    false    6            �            1259    19057    rango_facturas_id_seq    SEQUENCE     �   CREATE SEQUENCE public.rango_facturas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 ,   DROP SEQUENCE public.rango_facturas_id_seq;
       public          postgres    false    6    243            T           0    0    rango_facturas_id_seq    SEQUENCE OWNED BY     O   ALTER SEQUENCE public.rango_facturas_id_seq OWNED BY public.rango_facturas.id;
          public          postgres    false    242                       1259    20430    reclamos_clientes    TABLE     C  CREATE TABLE public.reclamos_clientes (
    id_reclamo integer NOT NULL,
    id_cliente integer NOT NULL,
    descripcion text NOT NULL,
    fecha_reclamo timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    estado character varying(20) DEFAULT 'pendiente'::character varying NOT NULL,
    respuesta text
);
 %   DROP TABLE public.reclamos_clientes;
       public            postgres    false    6                       1259    20428     reclamos_clientes_id_reclamo_seq    SEQUENCE     �   CREATE SEQUENCE public.reclamos_clientes_id_reclamo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 7   DROP SEQUENCE public.reclamos_clientes_id_reclamo_seq;
       public          postgres    false    279    6            U           0    0     reclamos_clientes_id_reclamo_seq    SEQUENCE OWNED BY     e   ALTER SEQUENCE public.reclamos_clientes_id_reclamo_seq OWNED BY public.reclamos_clientes.id_reclamo;
          public          postgres    false    278            �            1259    19010    recuperacion_contrasena    TABLE     �   CREATE TABLE public.recuperacion_contrasena (
    id integer NOT NULL,
    email character varying(255) NOT NULL,
    token character varying(32) NOT NULL,
    expiry timestamp without time zone NOT NULL
);
 +   DROP TABLE public.recuperacion_contrasena;
       public            postgres    false    6            �            1259    19008    recuperacion_contrasena_id_seq    SEQUENCE     �   CREATE SEQUENCE public.recuperacion_contrasena_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 5   DROP SEQUENCE public.recuperacion_contrasena_id_seq;
       public          postgres    false    6    239            V           0    0    recuperacion_contrasena_id_seq    SEQUENCE OWNED BY     a   ALTER SEQUENCE public.recuperacion_contrasena_id_seq OWNED BY public.recuperacion_contrasena.id;
          public          postgres    false    238            	           1259    20205 	   servicios    TABLE     �   CREATE TABLE public.servicios (
    id integer NOT NULL,
    nombre character varying(255) NOT NULL,
    costo numeric(10,2) NOT NULL,
    tipo character varying(255)
);
    DROP TABLE public.servicios;
       public            postgres    false    6                       1259    20213    servicios_cabecera    TABLE       CREATE TABLE public.servicios_cabecera (
    id_cabecera integer NOT NULL,
    id_cliente integer NOT NULL,
    fecha date NOT NULL,
    estado character varying(20) DEFAULT 'pendiente'::character varying,
    descuento numeric(10,2),
    monto_total numeric(10,2)
);
 &   DROP TABLE public.servicios_cabecera;
       public            postgres    false    6            
           1259    20211 "   servicios_cabecera_id_cabecera_seq    SEQUENCE     �   CREATE SEQUENCE public.servicios_cabecera_id_cabecera_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 9   DROP SEQUENCE public.servicios_cabecera_id_cabecera_seq;
       public          postgres    false    267    6            W           0    0 "   servicios_cabecera_id_cabecera_seq    SEQUENCE OWNED BY     i   ALTER SEQUENCE public.servicios_cabecera_id_cabecera_seq OWNED BY public.servicios_cabecera.id_cabecera;
          public          postgres    false    266                       1259    20314    servicios_detalle    TABLE     �   CREATE TABLE public.servicios_detalle (
    id_detalle integer NOT NULL,
    id_cabecera integer NOT NULL,
    id_servicio integer,
    id_promocion integer,
    costo_servicio numeric(10,2),
    costo_promocion numeric(10,2)
);
 %   DROP TABLE public.servicios_detalle;
       public            postgres    false    6                       1259    20312     servicios_detalle_id_detalle_seq    SEQUENCE     �   CREATE SEQUENCE public.servicios_detalle_id_detalle_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 7   DROP SEQUENCE public.servicios_detalle_id_detalle_seq;
       public          postgres    false    6    273            X           0    0     servicios_detalle_id_detalle_seq    SEQUENCE OWNED BY     e   ALTER SEQUENCE public.servicios_detalle_id_detalle_seq OWNED BY public.servicios_detalle.id_detalle;
          public          postgres    false    272                       1259    20203    servicios_id_seq    SEQUENCE     �   CREATE SEQUENCE public.servicios_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 '   DROP SEQUENCE public.servicios_id_seq;
       public          postgres    false    265    6            Y           0    0    servicios_id_seq    SEQUENCE OWNED BY     E   ALTER SEQUENCE public.servicios_id_seq OWNED BY public.servicios.id;
          public          postgres    false    264            �            1259    18962    usuarios    TABLE     �  CREATE TABLE public.usuarios (
    id integer NOT NULL,
    nombre_usuario character varying(255) NOT NULL,
    contrasena character varying(255) NOT NULL,
    rol character varying(50) DEFAULT 'compra'::character varying NOT NULL,
    intentos_acceso integer DEFAULT 0,
    ultimo_acceso timestamp without time zone,
    estado boolean DEFAULT true,
    fecha_creacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    email character varying(255),
    telefono character varying(20),
    intentos_fallidos integer DEFAULT 0,
    bloqueado boolean DEFAULT false,
    imagen_perfil character varying(255)
);
    DROP TABLE public.usuarios;
       public            postgres    false    6            �            1259    18960    usuarios_id_seq    SEQUENCE     �   CREATE SEQUENCE public.usuarios_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 &   DROP SEQUENCE public.usuarios_id_seq;
       public          postgres    false    237    6            Z           0    0    usuarios_id_seq    SEQUENCE OWNED BY     C   ALTER SEQUENCE public.usuarios_id_seq OWNED BY public.usuarios.id;
          public          postgres    false    236            �            1259    19093    ventas    TABLE     �  CREATE TABLE public.ventas (
    id integer NOT NULL,
    cliente_id integer,
    fecha timestamp without time zone,
    forma_pago character varying(50),
    estado character varying(50) DEFAULT 'pendiente'::character varying,
    cuotas integer,
    numero_factura character varying(50),
    timbrado character varying(50),
    nota_credito_id integer,
    monto_nc_aplicado numeric(10,2) DEFAULT 0,
    metodo_pago character varying(50),
    solicitud_id integer,
    monto_total_final numeric
);
    DROP TABLE public.ventas;
       public            postgres    false    6            �            1259    19091    ventas_id_seq    SEQUENCE     �   CREATE SEQUENCE public.ventas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE public.ventas_id_seq;
       public          postgres    false    6    245            [           0    0    ventas_id_seq    SEQUENCE OWNED BY     ?   ALTER SEQUENCE public.ventas_id_seq OWNED BY public.ventas.id;
          public          postgres    false    244            �           2604    17667    ajustes_inventario id_ajuste    DEFAULT     �   ALTER TABLE ONLY public.ajustes_inventario ALTER COLUMN id_ajuste SET DEFAULT nextval('public.ajustes_inventario_id_ajuste_seq'::regclass);
 K   ALTER TABLE public.ajustes_inventario ALTER COLUMN id_ajuste DROP DEFAULT;
       public          postgres    false    228    227    228            �           2604    17384 )   aperturas_de_caja id_apertura_cierre_caja    DEFAULT     �   ALTER TABLE ONLY public.aperturas_de_caja ALTER COLUMN id_apertura_cierre_caja SET DEFAULT nextval('public.aperturas_de_caja_id_apertura_cierre_caja_seq'::regclass);
 X   ALTER TABLE public.aperturas_de_caja ALTER COLUMN id_apertura_cierre_caja DROP DEFAULT;
       public          postgres    false    206    207    207            �           2604    19040    cajas id_caja    DEFAULT     m   ALTER TABLE ONLY public.cajas ALTER COLUMN id_caja SET DEFAULT nextval('public.caja_id_caja_seq'::regclass);
 <   ALTER TABLE public.cajas ALTER COLUMN id_caja DROP DEFAULT;
       public          postgres    false    241    240    241            �           2604    17242    ciudades id_ciudad    DEFAULT     q   ALTER TABLE ONLY public.ciudades ALTER COLUMN id_ciudad SET DEFAULT nextval('public.ciudades_id_seq'::regclass);
 A   ALTER TABLE public.ciudades ALTER COLUMN id_ciudad DROP DEFAULT;
       public          postgres    false    201    200    201            �           2604    17398    clientes id_cliente    DEFAULT     z   ALTER TABLE ONLY public.clientes ALTER COLUMN id_cliente SET DEFAULT nextval('public.clientes_id_cliente_seq'::regclass);
 B   ALTER TABLE public.clientes ALTER COLUMN id_cliente DROP DEFAULT;
       public          postgres    false    209    208    209            �           2604    17599    compras id_compra    DEFAULT     v   ALTER TABLE ONLY public.compras ALTER COLUMN id_compra SET DEFAULT nextval('public.compras_id_compra_seq'::regclass);
 @   ALTER TABLE public.compras ALTER COLUMN id_compra DROP DEFAULT;
       public          postgres    false    220    221    221            �           2604    19170    cuentas_por_cobrar id    DEFAULT     ~   ALTER TABLE ONLY public.cuentas_por_cobrar ALTER COLUMN id SET DEFAULT nextval('public.cuentas_por_cobrar_id_seq'::regclass);
 D   ALTER TABLE public.cuentas_por_cobrar ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    251    250    251            �           2604    20257    descuentos id_descuento    DEFAULT     �   ALTER TABLE ONLY public.descuentos ALTER COLUMN id_descuento SET DEFAULT nextval('public.descuentos_id_descuento_seq'::regclass);
 F   ALTER TABLE public.descuentos ALTER COLUMN id_descuento DROP DEFAULT;
       public          postgres    false    271    270    271            �           2604    17617 !   detalle_compras id_detalle_compra    DEFAULT     �   ALTER TABLE ONLY public.detalle_compras ALTER COLUMN id_detalle_compra SET DEFAULT nextval('public.detalle_compras_id_detalle_compra_seq'::regclass);
 P   ALTER TABLE public.detalle_compras ALTER COLUMN id_detalle_compra DROP DEFAULT;
       public          postgres    false    223    222    223            �           2604    20181    detalle_notas_credito_debito id    DEFAULT     �   ALTER TABLE ONLY public.detalle_notas_credito_debito ALTER COLUMN id SET DEFAULT nextval('public.detalle_notas_credito_debito_id_seq'::regclass);
 N   ALTER TABLE public.detalle_notas_credito_debito ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    262    263    263            �           2604    17581    detalle_orden_compra id_detalle    DEFAULT     �   ALTER TABLE ONLY public.detalle_orden_compra ALTER COLUMN id_detalle SET DEFAULT nextval('public.detalle_orden_compra_id_detalle_seq'::regclass);
 N   ALTER TABLE public.detalle_orden_compra ALTER COLUMN id_detalle DROP DEFAULT;
       public          postgres    false    219    218    219            �           2604    17481    detalle_pedido_interno id    DEFAULT     �   ALTER TABLE ONLY public.detalle_pedido_interno ALTER COLUMN id SET DEFAULT nextval('public.detalle_pedido_interno_id_seq'::regclass);
 H   ALTER TABLE public.detalle_pedido_interno ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    215    214    215            �           2604    19124    detalle_venta id    DEFAULT     t   ALTER TABLE ONLY public.detalle_venta ALTER COLUMN id SET DEFAULT nextval('public.detalle_venta_id_seq'::regclass);
 ?   ALTER TABLE public.detalle_venta ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    247    246    247            �           2604    17460    entrega_cheques id_entrega    DEFAULT     �   ALTER TABLE ONLY public.entrega_cheques ALTER COLUMN id_entrega SET DEFAULT nextval('public.entrega_cheques_id_entrega_seq'::regclass);
 I   ALTER TABLE public.entrega_cheques ALTER COLUMN id_entrega DROP DEFAULT;
       public          postgres    false    211    212    212            �           2604    17643    libro_compras id_libro_compra    DEFAULT     �   ALTER TABLE ONLY public.libro_compras ALTER COLUMN id_libro_compra SET DEFAULT nextval('public.libro_compras_id_libro_compra_seq'::regclass);
 L   ALTER TABLE public.libro_compras ALTER COLUMN id_libro_compra DROP DEFAULT;
       public          postgres    false    226    225    226            �           2604    19149    libro_ventas id    DEFAULT     r   ALTER TABLE ONLY public.libro_ventas ALTER COLUMN id SET DEFAULT nextval('public.libro_ventas_id_seq'::regclass);
 >   ALTER TABLE public.libro_ventas ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    249    248    249            �           2604    17710    nota_remision id_nota_remision    DEFAULT     �   ALTER TABLE ONLY public.nota_remision ALTER COLUMN id_nota_remision SET DEFAULT nextval('public.nota_remision_id_nota_remision_seq'::regclass);
 M   ALTER TABLE public.nota_remision ALTER COLUMN id_nota_remision DROP DEFAULT;
       public          postgres    false    232    231    232            �           2604    20068 "   nota_remision_cabecera id_remision    DEFAULT     �   ALTER TABLE ONLY public.nota_remision_cabecera ALTER COLUMN id_remision SET DEFAULT nextval('public.nota_remision_cabecera_id_remision_seq'::regclass);
 Q   ALTER TABLE public.nota_remision_cabecera ALTER COLUMN id_remision DROP DEFAULT;
       public          postgres    false    254    255    255            �           2604    17742     nota_remision_detalle id_detalle    DEFAULT     �   ALTER TABLE ONLY public.nota_remision_detalle ALTER COLUMN id_detalle SET DEFAULT nextval('public.nota_remision_detalle_id_detalle_seq'::regclass);
 O   ALTER TABLE public.nota_remision_detalle ALTER COLUMN id_detalle DROP DEFAULT;
       public          postgres    false    234    233    234            �           2604    20083 (   nota_remision_venta_cabecera id_remision    DEFAULT     �   ALTER TABLE ONLY public.nota_remision_venta_cabecera ALTER COLUMN id_remision SET DEFAULT nextval('public.nota_remision_venta_cabecera_id_remision_seq'::regclass);
 W   ALTER TABLE public.nota_remision_venta_cabecera ALTER COLUMN id_remision DROP DEFAULT;
       public          postgres    false    257    256    257            �           2604    20098    nota_remision_venta_detalle id    DEFAULT     �   ALTER TABLE ONLY public.nota_remision_venta_detalle ALTER COLUMN id SET DEFAULT nextval('public.nota_remision_venta_detalle_id_seq'::regclass);
 M   ALTER TABLE public.nota_remision_venta_detalle ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    259    258    259            �           2604    17681    notas id_nota    DEFAULT     n   ALTER TABLE ONLY public.notas ALTER COLUMN id_nota SET DEFAULT nextval('public.notas_id_nota_seq'::regclass);
 <   ALTER TABLE public.notas ALTER COLUMN id_nota DROP DEFAULT;
       public          postgres    false    229    230    230            �           2604    20155    notas_credito_debito id    DEFAULT     �   ALTER TABLE ONLY public.notas_credito_debito ALTER COLUMN id SET DEFAULT nextval('public.notas_credito_debito_id_seq'::regclass);
 F   ALTER TABLE public.notas_credito_debito ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    261    260    261            �           2604    20451    orden_servicio id_orden    DEFAULT     �   ALTER TABLE ONLY public.orden_servicio ALTER COLUMN id_orden SET DEFAULT nextval('public.orden_servicio_id_orden_seq'::regclass);
 F   ALTER TABLE public.orden_servicio ALTER COLUMN id_orden DROP DEFAULT;
       public          postgres    false    281    280    281            �           2604    17537    ordenes_compra id_orden_compra    DEFAULT     �   ALTER TABLE ONLY public.ordenes_compra ALTER COLUMN id_orden_compra SET DEFAULT nextval('public.ordenes_compra_id_orden_compra_seq'::regclass);
 M   ALTER TABLE public.ordenes_compra ALTER COLUMN id_orden_compra DROP DEFAULT;
       public          postgres    false    216    217    217            �           2604    19190    pagos id    DEFAULT     d   ALTER TABLE ONLY public.pagos ALTER COLUMN id SET DEFAULT nextval('public.pagos_id_seq'::regclass);
 7   ALTER TABLE public.pagos ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    252    253    253            �           2604    17234    paises id_pais    DEFAULT     k   ALTER TABLE ONLY public.paises ALTER COLUMN id_pais SET DEFAULT nextval('public.paises_id_seq'::regclass);
 =   ALTER TABLE public.paises ALTER COLUMN id_pais DROP DEFAULT;
       public          postgres    false    198    199    199            �           2604    18061 *   presupuesto_detalle id_presupuesto_detalle    DEFAULT     �   ALTER TABLE ONLY public.presupuesto_detalle ALTER COLUMN id_presupuesto_detalle SET DEFAULT nextval('public.presupuesto_detalle_id_presupuesto_detalle_seq'::regclass);
 Y   ALTER TABLE public.presupuesto_detalle ALTER COLUMN id_presupuesto_detalle DROP DEFAULT;
       public          postgres    false    235    210            �           2604    17345    presupuestos id_presupuesto    DEFAULT     �   ALTER TABLE ONLY public.presupuestos ALTER COLUMN id_presupuesto SET DEFAULT nextval('public.presupuestos_id_presupuesto_seq'::regclass);
 J   ALTER TABLE public.presupuestos ALTER COLUMN id_presupuesto DROP DEFAULT;
       public          postgres    false    205    204    205            �           2604    17260    producto id_producto    DEFAULT     |   ALTER TABLE ONLY public.producto ALTER COLUMN id_producto SET DEFAULT nextval('public.producto_id_producto_seq'::regclass);
 C   ALTER TABLE public.producto ALTER COLUMN id_producto DROP DEFAULT;
       public          postgres    false    203    202    203            �           2604    20247    promociones id_promocion    DEFAULT     �   ALTER TABLE ONLY public.promociones ALTER COLUMN id_promocion SET DEFAULT nextval('public.promociones_id_promocion_seq'::regclass);
 G   ALTER TABLE public.promociones ALTER COLUMN id_promocion DROP DEFAULT;
       public          postgres    false    268    269    269            �           2604    17223    proveedores id_proveedor    DEFAULT     z   ALTER TABLE ONLY public.proveedores ALTER COLUMN id_proveedor SET DEFAULT nextval('public.proveedores_id_seq'::regclass);
 G   ALTER TABLE public.proveedores ALTER COLUMN id_proveedor DROP DEFAULT;
       public          postgres    false    196    197    197            �           2604    19062    rango_facturas id    DEFAULT     v   ALTER TABLE ONLY public.rango_facturas ALTER COLUMN id SET DEFAULT nextval('public.rango_facturas_id_seq'::regclass);
 @   ALTER TABLE public.rango_facturas ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    243    242    243            �           2604    20433    reclamos_clientes id_reclamo    DEFAULT     �   ALTER TABLE ONLY public.reclamos_clientes ALTER COLUMN id_reclamo SET DEFAULT nextval('public.reclamos_clientes_id_reclamo_seq'::regclass);
 K   ALTER TABLE public.reclamos_clientes ALTER COLUMN id_reclamo DROP DEFAULT;
       public          postgres    false    279    278    279            �           2604    19013    recuperacion_contrasena id    DEFAULT     �   ALTER TABLE ONLY public.recuperacion_contrasena ALTER COLUMN id SET DEFAULT nextval('public.recuperacion_contrasena_id_seq'::regclass);
 I   ALTER TABLE public.recuperacion_contrasena ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    239    238    239            �           2604    20208    servicios id    DEFAULT     l   ALTER TABLE ONLY public.servicios ALTER COLUMN id SET DEFAULT nextval('public.servicios_id_seq'::regclass);
 ;   ALTER TABLE public.servicios ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    265    264    265            �           2604    20216    servicios_cabecera id_cabecera    DEFAULT     �   ALTER TABLE ONLY public.servicios_cabecera ALTER COLUMN id_cabecera SET DEFAULT nextval('public.servicios_cabecera_id_cabecera_seq'::regclass);
 M   ALTER TABLE public.servicios_cabecera ALTER COLUMN id_cabecera DROP DEFAULT;
       public          postgres    false    266    267    267            �           2604    20317    servicios_detalle id_detalle    DEFAULT     �   ALTER TABLE ONLY public.servicios_detalle ALTER COLUMN id_detalle SET DEFAULT nextval('public.servicios_detalle_id_detalle_seq'::regclass);
 K   ALTER TABLE public.servicios_detalle ALTER COLUMN id_detalle DROP DEFAULT;
       public          postgres    false    272    273    273            �           2604    18965    usuarios id    DEFAULT     j   ALTER TABLE ONLY public.usuarios ALTER COLUMN id SET DEFAULT nextval('public.usuarios_id_seq'::regclass);
 :   ALTER TABLE public.usuarios ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    237    236    237            �           2604    19096 	   ventas id    DEFAULT     f   ALTER TABLE ONLY public.ventas ALTER COLUMN id SET DEFAULT nextval('public.ventas_id_seq'::regclass);
 8   ALTER TABLE public.ventas ALTER COLUMN id DROP DEFAULT;
       public          postgres    false    244    245    245            �          0    17664    ajustes_inventario 
   TABLE DATA           t   COPY public.ajustes_inventario (id_ajuste, id_producto, cantidad_ajustada, fecha_ajuste, motivo_ajuste) FROM stdin;
    public          postgres    false    228   u      �          0    17381    aperturas_de_caja 
   TABLE DATA           �   COPY public.aperturas_de_caja (id_apertura_cierre_caja, numero_caja, nombre_usuario, estado, fecha_apertura, hora_apertura, fecha_cierre, hora_cierre, monto_inicial) FROM stdin;
    public          postgres    false    207   D       �          0    17471    cabecera_pedido_interno 
   TABLE DATA           �   COPY public.cabecera_pedido_interno (numero_pedido, departamento_solicitante, telefono, correo, fecha_pedido, fecha_entrega_solicitada) FROM stdin;
    public          postgres    false    213   �                 0    19037    cajas 
   TABLE DATA           �   COPY public.cajas (id_caja, fecha_apertura, hora_apertura, monto_inicial, fecha_cierre, hora_cierre, monto_final, estado, usuario) FROM stdin;
    public          postgres    false    241   6!      �          0    17239    ciudades 
   TABLE DATA           5   COPY public.ciudades (id_ciudad, nombre) FROM stdin;
    public          postgres    false    201   "      �          0    17395    clientes 
   TABLE DATA           ]   COPY public.clientes (id_cliente, nombre, apellido, direccion, telefono, ruc_ci) FROM stdin;
    public          postgres    false    209   ]"      �          0    17596    compras 
   TABLE DATA           �   COPY public.compras (id_compra, numero_factura, fecha_factura, id_proveedor, id_orden_compra, condicion_pago, cantidad_cuotas) FROM stdin;
    public          postgres    false    221   V#                0    19167    cuentas_por_cobrar 
   TABLE DATA           v   COPY public.cuentas_por_cobrar (id, venta_id, numero_cuota, fecha_vencimiento, monto, estado, fecha_pago) FROM stdin;
    public          postgres    false    251   8$      "          0    20254 
   descuentos 
   TABLE DATA           N   COPY public.descuentos (id_descuento, nombre, porcentaje, estado) FROM stdin;
    public          postgres    false    271   %      �          0    17614    detalle_compras 
   TABLE DATA           |   COPY public.detalle_compras (id_detalle_compra, id_compra, id_producto, descripcion, cantidad, precio_unitario) FROM stdin;
    public          postgres    false    223   H%                0    20178    detalle_notas_credito_debito 
   TABLE DATA           r   COPY public.detalle_notas_credito_debito (id, nota_id, producto_id, cantidad, precio_unitario, monto) FROM stdin;
    public          postgres    false    263   �&      �          0    17578    detalle_orden_compra 
   TABLE DATA           �   COPY public.detalle_orden_compra (id_detalle, id_orden_compra, id_producto, descripcion, cantidad, precio_unitario) FROM stdin;
    public          postgres    false    219   i'      �          0    17478    detalle_pedido_interno 
   TABLE DATA           k   COPY public.detalle_pedido_interno (id, numero_pedido, id_producto, nombre_producto, cantidad) FROM stdin;
    public          postgres    false    215   I(      
          0    19121    detalle_venta 
   TABLE DATA           ]   COPY public.detalle_venta (id, venta_id, producto_id, cantidad, precio_unitario) FROM stdin;
    public          postgres    false    247   �(      �          0    17457    entrega_cheques 
   TABLE DATA           u   COPY public.entrega_cheques (id_entrega, id_proveedor, monto, fecha_entrega, numero_cheque, descripcion) FROM stdin;
    public          postgres    false    212   *      �          0    17630 
   inventario 
   TABLE DATA           ;   COPY public.inventario (id_producto, cantidad) FROM stdin;
    public          postgres    false    224   J*      �          0    17640    libro_compras 
   TABLE DATA           Z   COPY public.libro_compras (id_libro_compra, id_compra, fecha_registro, total) FROM stdin;
    public          postgres    false    226   �*                0    19146    libro_ventas 
   TABLE DATA           �   COPY public.libro_ventas (id, numero_factura, timbrado, cliente_id, cliente_nombre, fecha, forma_pago, monto_total, estado, created_at) FROM stdin;
    public          postgres    false    249   �+      �          0    17707    nota_remision 
   TABLE DATA           {   COPY public.nota_remision (id_nota_remision, numero_remision, fecha_remision, id_proveedor, id_compra, estado) FROM stdin;
    public          postgres    false    232   ~.                0    20065    nota_remision_cabecera 
   TABLE DATA           h   COPY public.nota_remision_cabecera (id_remision, cliente_id, fecha, estado, numero_factura) FROM stdin;
    public          postgres    false    255   �.      �          0    17739    nota_remision_detalle 
   TABLE DATA           �   COPY public.nota_remision_detalle (id_detalle, id_nota_remision, id_producto, nombre_producto, cantidad, precio_unitario) FROM stdin;
    public          postgres    false    234   /                0    20080    nota_remision_venta_cabecera 
   TABLE DATA           n   COPY public.nota_remision_venta_cabecera (id_remision, cliente_id, fecha, estado, numero_factura) FROM stdin;
    public          postgres    false    257   �/                0    20095    nota_remision_venta_detalle 
   TABLE DATA           n   COPY public.nota_remision_venta_detalle (id, remision_id, producto_id, cantidad, precio_unitario) FROM stdin;
    public          postgres    false    259   g0      �          0    17678    notas 
   TABLE DATA           �   COPY public.notas (id_nota, tipo_nota, numero_nota, fecha_nota, id_proveedor, id_compra, monto, descripcion, estado) FROM stdin;
    public          postgres    false    230   �0                0    20152    notas_credito_debito 
   TABLE DATA           ~   COPY public.notas_credito_debito (id, cliente_id, tipo, fecha, estado, monto, motivo, venta_id, fecha_aplicacion) FROM stdin;
    public          postgres    false    261   �1      ,          0    20448    orden_servicio 
   TABLE DATA           m   COPY public.orden_servicio (id_orden, id_solicitud, id_trabajador, fecha, estado, observaciones) FROM stdin;
    public          postgres    false    281   �3      �          0    17534    ordenes_compra 
   TABLE DATA           �   COPY public.ordenes_compra (id_orden_compra, fecha_emision, fecha_entrega, condiciones_entrega, metodo_pago, cuotas, estado_orden, id_proveedor, id_presupuesto) FROM stdin;
    public          postgres    false    217   �4                0    19187    pagos 
   TABLE DATA           _   COPY public.pagos (id, cuenta_id, monto_pago, fecha_pago, forma_pago, estado_pago) FROM stdin;
    public          postgres    false    253   �5      �          0    17231    paises 
   TABLE DATA           =   COPY public.paises (id_pais, nombre, gentilicio) FROM stdin;
    public          postgres    false    199   �6      &          0    20393    presupuesto_cabecera_servicio 
   TABLE DATA           w   COPY public.presupuesto_cabecera_servicio (id_cabecera, id_cliente, fecha, estado, descuento, monto_total) FROM stdin;
    public          postgres    false    275   �6      �          0    17439    presupuesto_detalle 
   TABLE DATA           �   COPY public.presupuesto_detalle (id_presupuesto, id_producto, cantidad, precio_unitario, precio_total, id_presupuesto_detalle) FROM stdin;
    public          postgres    false    210   V7      (          0    20407    presupuesto_detalle_servicio 
   TABLE DATA           �   COPY public.presupuesto_detalle_servicio (id_detalle, id_cabecera, id_servicio, id_promocion, costo_servicio, costo_promocion) FROM stdin;
    public          postgres    false    277   �8      �          0    17342    presupuestos 
   TABLE DATA           m   COPY public.presupuestos (id_presupuesto, id_proveedor, fecharegistro, fechavencimiento, estado) FROM stdin;
    public          postgres    false    205   $9      �          0    17257    producto 
   TABLE DATA           �   COPY public.producto (id_producto, nombre, precio_unitario, precio_compra, estado, tipo_iva, medida, color, material, hilos, categoria) FROM stdin;
    public          postgres    false    203   �:                 0    20244    promociones 
   TABLE DATA           K   COPY public.promociones (id_promocion, nombre, precio, estado) FROM stdin;
    public          postgres    false    269   �;      �          0    17220    proveedores 
   TABLE DATA           p   COPY public.proveedores (id_proveedor, nombre, direccion, telefono, email, ruc, id_pais, id_ciudad) FROM stdin;
    public          postgres    false    197   �;                0    19059    rango_facturas 
   TABLE DATA           x   COPY public.rango_facturas (id, timbrado, rango_inicio, rango_fin, actual, fecha_inicio, fecha_fin, activo) FROM stdin;
    public          postgres    false    243   L=      *          0    20430    reclamos_clientes 
   TABLE DATA           r   COPY public.reclamos_clientes (id_reclamo, id_cliente, descripcion, fecha_reclamo, estado, respuesta) FROM stdin;
    public          postgres    false    279   �=                0    19010    recuperacion_contrasena 
   TABLE DATA           K   COPY public.recuperacion_contrasena (id, email, token, expiry) FROM stdin;
    public          postgres    false    239   )>                0    20205 	   servicios 
   TABLE DATA           <   COPY public.servicios (id, nombre, costo, tipo) FROM stdin;
    public          postgres    false    265   �>                0    20213    servicios_cabecera 
   TABLE DATA           l   COPY public.servicios_cabecera (id_cabecera, id_cliente, fecha, estado, descuento, monto_total) FROM stdin;
    public          postgres    false    267   ?      $          0    20314    servicios_detalle 
   TABLE DATA           �   COPY public.servicios_detalle (id_detalle, id_cabecera, id_servicio, id_promocion, costo_servicio, costo_promocion) FROM stdin;
    public          postgres    false    273   �?                 0    18962    usuarios 
   TABLE DATA           �   COPY public.usuarios (id, nombre_usuario, contrasena, rol, intentos_acceso, ultimo_acceso, estado, fecha_creacion, fecha_actualizacion, email, telefono, intentos_fallidos, bloqueado, imagen_perfil) FROM stdin;
    public          postgres    false    237   j@                0    19093    ventas 
   TABLE DATA           �   COPY public.ventas (id, cliente_id, fecha, forma_pago, estado, cuotas, numero_factura, timbrado, nota_credito_id, monto_nc_aplicado, metodo_pago, solicitud_id, monto_total_final) FROM stdin;
    public          postgres    false    245   TB      \           0    0     ajustes_inventario_id_ajuste_seq    SEQUENCE SET     O   SELECT pg_catalog.setval('public.ajustes_inventario_id_ajuste_seq', 15, true);
          public          postgres    false    227            ]           0    0 -   aperturas_de_caja_id_apertura_cierre_caja_seq    SEQUENCE SET     [   SELECT pg_catalog.setval('public.aperturas_de_caja_id_apertura_cierre_caja_seq', 3, true);
          public          postgres    false    206            ^           0    0    caja_id_caja_seq    SEQUENCE SET     ?   SELECT pg_catalog.setval('public.caja_id_caja_seq', 14, true);
          public          postgres    false    240            _           0    0    ciudades_id_seq    SEQUENCE SET     >   SELECT pg_catalog.setval('public.ciudades_id_seq', 1, false);
          public          postgres    false    200            `           0    0    clientes_id_cliente_seq    SEQUENCE SET     F   SELECT pg_catalog.setval('public.clientes_id_cliente_seq', 45, true);
          public          postgres    false    208            a           0    0    compras_id_compra_seq    SEQUENCE SET     D   SELECT pg_catalog.setval('public.compras_id_compra_seq', 31, true);
          public          postgres    false    220            b           0    0    cuentas_por_cobrar_id_seq    SEQUENCE SET     H   SELECT pg_catalog.setval('public.cuentas_por_cobrar_id_seq', 29, true);
          public          postgres    false    250            c           0    0    descuentos_id_descuento_seq    SEQUENCE SET     I   SELECT pg_catalog.setval('public.descuentos_id_descuento_seq', 1, true);
          public          postgres    false    270            d           0    0 %   detalle_compras_id_detalle_compra_seq    SEQUENCE SET     T   SELECT pg_catalog.setval('public.detalle_compras_id_detalle_compra_seq', 52, true);
          public          postgres    false    222            e           0    0 #   detalle_notas_credito_debito_id_seq    SEQUENCE SET     R   SELECT pg_catalog.setval('public.detalle_notas_credito_debito_id_seq', 29, true);
          public          postgres    false    262            f           0    0 #   detalle_orden_compra_id_detalle_seq    SEQUENCE SET     R   SELECT pg_catalog.setval('public.detalle_orden_compra_id_detalle_seq', 25, true);
          public          postgres    false    218            g           0    0    detalle_pedido_interno_id_seq    SEQUENCE SET     M   SELECT pg_catalog.setval('public.detalle_pedido_interno_id_seq', 170, true);
          public          postgres    false    214            h           0    0    detalle_venta_id_seq    SEQUENCE SET     C   SELECT pg_catalog.setval('public.detalle_venta_id_seq', 66, true);
          public          postgres    false    246            i           0    0    entrega_cheques_id_entrega_seq    SEQUENCE SET     L   SELECT pg_catalog.setval('public.entrega_cheques_id_entrega_seq', 3, true);
          public          postgres    false    211            j           0    0 !   libro_compras_id_libro_compra_seq    SEQUENCE SET     P   SELECT pg_catalog.setval('public.libro_compras_id_libro_compra_seq', 44, true);
          public          postgres    false    225            k           0    0    libro_ventas_id_seq    SEQUENCE SET     B   SELECT pg_catalog.setval('public.libro_ventas_id_seq', 42, true);
          public          postgres    false    248            l           0    0 &   nota_remision_cabecera_id_remision_seq    SEQUENCE SET     T   SELECT pg_catalog.setval('public.nota_remision_cabecera_id_remision_seq', 1, true);
          public          postgres    false    254            m           0    0 $   nota_remision_detalle_id_detalle_seq    SEQUENCE SET     S   SELECT pg_catalog.setval('public.nota_remision_detalle_id_detalle_seq', 18, true);
          public          postgres    false    233            n           0    0 "   nota_remision_id_nota_remision_seq    SEQUENCE SET     P   SELECT pg_catalog.setval('public.nota_remision_id_nota_remision_seq', 6, true);
          public          postgres    false    231            o           0    0 ,   nota_remision_venta_cabecera_id_remision_seq    SEQUENCE SET     Z   SELECT pg_catalog.setval('public.nota_remision_venta_cabecera_id_remision_seq', 8, true);
          public          postgres    false    256            p           0    0 "   nota_remision_venta_detalle_id_seq    SEQUENCE SET     Q   SELECT pg_catalog.setval('public.nota_remision_venta_detalle_id_seq', 13, true);
          public          postgres    false    258            q           0    0    notas_credito_debito_id_seq    SEQUENCE SET     J   SELECT pg_catalog.setval('public.notas_credito_debito_id_seq', 35, true);
          public          postgres    false    260            r           0    0    notas_id_nota_seq    SEQUENCE SET     @   SELECT pg_catalog.setval('public.notas_id_nota_seq', 13, true);
          public          postgres    false    229            s           0    0    orden_servicio_id_orden_seq    SEQUENCE SET     J   SELECT pg_catalog.setval('public.orden_servicio_id_orden_seq', 10, true);
          public          postgres    false    280            t           0    0 "   ordenes_compra_id_orden_compra_seq    SEQUENCE SET     Q   SELECT pg_catalog.setval('public.ordenes_compra_id_orden_compra_seq', 1, false);
          public          postgres    false    216            u           0    0    pagos_id_seq    SEQUENCE SET     ;   SELECT pg_catalog.setval('public.pagos_id_seq', 43, true);
          public          postgres    false    252            v           0    0    paises_id_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('public.paises_id_seq', 1, false);
          public          postgres    false    198            w           0    0 -   presupuesto_cabecera_servicio_id_cabecera_seq    SEQUENCE SET     [   SELECT pg_catalog.setval('public.presupuesto_cabecera_servicio_id_cabecera_seq', 2, true);
          public          postgres    false    274            x           0    0 .   presupuesto_detalle_id_presupuesto_detalle_seq    SEQUENCE SET     ]   SELECT pg_catalog.setval('public.presupuesto_detalle_id_presupuesto_detalle_seq', 42, true);
          public          postgres    false    235            y           0    0 +   presupuesto_detalle_servicio_id_detalle_seq    SEQUENCE SET     Y   SELECT pg_catalog.setval('public.presupuesto_detalle_servicio_id_detalle_seq', 3, true);
          public          postgres    false    276            z           0    0    presupuestos_id_presupuesto_seq    SEQUENCE SET     N   SELECT pg_catalog.setval('public.presupuestos_id_presupuesto_seq', 65, true);
          public          postgres    false    204            {           0    0    producto_id_producto_seq    SEQUENCE SET     G   SELECT pg_catalog.setval('public.producto_id_producto_seq', 1, false);
          public          postgres    false    202            |           0    0    promociones_id_promocion_seq    SEQUENCE SET     J   SELECT pg_catalog.setval('public.promociones_id_promocion_seq', 1, true);
          public          postgres    false    268            }           0    0    proveedores_id_seq    SEQUENCE SET     A   SELECT pg_catalog.setval('public.proveedores_id_seq', 11, true);
          public          postgres    false    196            ~           0    0    rango_facturas_id_seq    SEQUENCE SET     C   SELECT pg_catalog.setval('public.rango_facturas_id_seq', 4, true);
          public          postgres    false    242                       0    0     reclamos_clientes_id_reclamo_seq    SEQUENCE SET     N   SELECT pg_catalog.setval('public.reclamos_clientes_id_reclamo_seq', 4, true);
          public          postgres    false    278            �           0    0    recuperacion_contrasena_id_seq    SEQUENCE SET     M   SELECT pg_catalog.setval('public.recuperacion_contrasena_id_seq', 35, true);
          public          postgres    false    238            �           0    0 "   servicios_cabecera_id_cabecera_seq    SEQUENCE SET     Q   SELECT pg_catalog.setval('public.servicios_cabecera_id_cabecera_seq', 55, true);
          public          postgres    false    266            �           0    0     servicios_detalle_id_detalle_seq    SEQUENCE SET     O   SELECT pg_catalog.setval('public.servicios_detalle_id_detalle_seq', 67, true);
          public          postgres    false    272            �           0    0    servicios_id_seq    SEQUENCE SET     >   SELECT pg_catalog.setval('public.servicios_id_seq', 4, true);
          public          postgres    false    264            �           0    0    usuarios_id_seq    SEQUENCE SET     >   SELECT pg_catalog.setval('public.usuarios_id_seq', 32, true);
          public          postgres    false    236            �           0    0    ventas_id_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('public.ventas_id_seq', 85, true);
          public          postgres    false    244            �           2606    17669 *   ajustes_inventario ajustes_inventario_pkey 
   CONSTRAINT     o   ALTER TABLE ONLY public.ajustes_inventario
    ADD CONSTRAINT ajustes_inventario_pkey PRIMARY KEY (id_ajuste);
 T   ALTER TABLE ONLY public.ajustes_inventario DROP CONSTRAINT ajustes_inventario_pkey;
       public            postgres    false    228            �           2606    17387 (   aperturas_de_caja aperturas_de_caja_pkey 
   CONSTRAINT     {   ALTER TABLE ONLY public.aperturas_de_caja
    ADD CONSTRAINT aperturas_de_caja_pkey PRIMARY KEY (id_apertura_cierre_caja);
 R   ALTER TABLE ONLY public.aperturas_de_caja DROP CONSTRAINT aperturas_de_caja_pkey;
       public            postgres    false    207            �           2606    17492 4   cabecera_pedido_interno cabecera_pedido_interno_pkey 
   CONSTRAINT     }   ALTER TABLE ONLY public.cabecera_pedido_interno
    ADD CONSTRAINT cabecera_pedido_interno_pkey PRIMARY KEY (numero_pedido);
 ^   ALTER TABLE ONLY public.cabecera_pedido_interno DROP CONSTRAINT cabecera_pedido_interno_pkey;
       public            postgres    false    213            �           2606    19043    cajas caja_pkey 
   CONSTRAINT     R   ALTER TABLE ONLY public.cajas
    ADD CONSTRAINT caja_pkey PRIMARY KEY (id_caja);
 9   ALTER TABLE ONLY public.cajas DROP CONSTRAINT caja_pkey;
       public            postgres    false    241            �           2606    17244    ciudades ciudades_pkey 
   CONSTRAINT     [   ALTER TABLE ONLY public.ciudades
    ADD CONSTRAINT ciudades_pkey PRIMARY KEY (id_ciudad);
 @   ALTER TABLE ONLY public.ciudades DROP CONSTRAINT ciudades_pkey;
       public            postgres    false    201            �           2606    17400    clientes clientes_pkey 
   CONSTRAINT     \   ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT clientes_pkey PRIMARY KEY (id_cliente);
 @   ALTER TABLE ONLY public.clientes DROP CONSTRAINT clientes_pkey;
       public            postgres    false    209            �           2606    17601    compras compras_pkey 
   CONSTRAINT     Y   ALTER TABLE ONLY public.compras
    ADD CONSTRAINT compras_pkey PRIMARY KEY (id_compra);
 >   ALTER TABLE ONLY public.compras DROP CONSTRAINT compras_pkey;
       public            postgres    false    221            	           2606    19172 *   cuentas_por_cobrar cuentas_por_cobrar_pkey 
   CONSTRAINT     h   ALTER TABLE ONLY public.cuentas_por_cobrar
    ADD CONSTRAINT cuentas_por_cobrar_pkey PRIMARY KEY (id);
 T   ALTER TABLE ONLY public.cuentas_por_cobrar DROP CONSTRAINT cuentas_por_cobrar_pkey;
       public            postgres    false    251                       2606    20261    descuentos descuentos_pkey 
   CONSTRAINT     b   ALTER TABLE ONLY public.descuentos
    ADD CONSTRAINT descuentos_pkey PRIMARY KEY (id_descuento);
 D   ALTER TABLE ONLY public.descuentos DROP CONSTRAINT descuentos_pkey;
       public            postgres    false    271            �           2606    17619 $   detalle_compras detalle_compras_pkey 
   CONSTRAINT     q   ALTER TABLE ONLY public.detalle_compras
    ADD CONSTRAINT detalle_compras_pkey PRIMARY KEY (id_detalle_compra);
 N   ALTER TABLE ONLY public.detalle_compras DROP CONSTRAINT detalle_compras_pkey;
       public            postgres    false    223                       2606    20183 >   detalle_notas_credito_debito detalle_notas_credito_debito_pkey 
   CONSTRAINT     |   ALTER TABLE ONLY public.detalle_notas_credito_debito
    ADD CONSTRAINT detalle_notas_credito_debito_pkey PRIMARY KEY (id);
 h   ALTER TABLE ONLY public.detalle_notas_credito_debito DROP CONSTRAINT detalle_notas_credito_debito_pkey;
       public            postgres    false    263            �           2606    17583 .   detalle_orden_compra detalle_orden_compra_pkey 
   CONSTRAINT     t   ALTER TABLE ONLY public.detalle_orden_compra
    ADD CONSTRAINT detalle_orden_compra_pkey PRIMARY KEY (id_detalle);
 X   ALTER TABLE ONLY public.detalle_orden_compra DROP CONSTRAINT detalle_orden_compra_pkey;
       public            postgres    false    219            �           2606    17483 2   detalle_pedido_interno detalle_pedido_interno_pkey 
   CONSTRAINT     p   ALTER TABLE ONLY public.detalle_pedido_interno
    ADD CONSTRAINT detalle_pedido_interno_pkey PRIMARY KEY (id);
 \   ALTER TABLE ONLY public.detalle_pedido_interno DROP CONSTRAINT detalle_pedido_interno_pkey;
       public            postgres    false    215                       2606    19126     detalle_venta detalle_venta_pkey 
   CONSTRAINT     ^   ALTER TABLE ONLY public.detalle_venta
    ADD CONSTRAINT detalle_venta_pkey PRIMARY KEY (id);
 J   ALTER TABLE ONLY public.detalle_venta DROP CONSTRAINT detalle_venta_pkey;
       public            postgres    false    247            �           2606    17465 $   entrega_cheques entrega_cheques_pkey 
   CONSTRAINT     j   ALTER TABLE ONLY public.entrega_cheques
    ADD CONSTRAINT entrega_cheques_pkey PRIMARY KEY (id_entrega);
 N   ALTER TABLE ONLY public.entrega_cheques DROP CONSTRAINT entrega_cheques_pkey;
       public            postgres    false    212            �           2606    17635    inventario inventario_pkey 
   CONSTRAINT     a   ALTER TABLE ONLY public.inventario
    ADD CONSTRAINT inventario_pkey PRIMARY KEY (id_producto);
 D   ALTER TABLE ONLY public.inventario DROP CONSTRAINT inventario_pkey;
       public            postgres    false    224            �           2606    17645     libro_compras libro_compras_pkey 
   CONSTRAINT     k   ALTER TABLE ONLY public.libro_compras
    ADD CONSTRAINT libro_compras_pkey PRIMARY KEY (id_libro_compra);
 J   ALTER TABLE ONLY public.libro_compras DROP CONSTRAINT libro_compras_pkey;
       public            postgres    false    226                       2606    19152    libro_ventas libro_ventas_pkey 
   CONSTRAINT     \   ALTER TABLE ONLY public.libro_ventas
    ADD CONSTRAINT libro_ventas_pkey PRIMARY KEY (id);
 H   ALTER TABLE ONLY public.libro_ventas DROP CONSTRAINT libro_ventas_pkey;
       public            postgres    false    249                       2606    20072 2   nota_remision_cabecera nota_remision_cabecera_pkey 
   CONSTRAINT     y   ALTER TABLE ONLY public.nota_remision_cabecera
    ADD CONSTRAINT nota_remision_cabecera_pkey PRIMARY KEY (id_remision);
 \   ALTER TABLE ONLY public.nota_remision_cabecera DROP CONSTRAINT nota_remision_cabecera_pkey;
       public            postgres    false    255            �           2606    17744 0   nota_remision_detalle nota_remision_detalle_pkey 
   CONSTRAINT     v   ALTER TABLE ONLY public.nota_remision_detalle
    ADD CONSTRAINT nota_remision_detalle_pkey PRIMARY KEY (id_detalle);
 Z   ALTER TABLE ONLY public.nota_remision_detalle DROP CONSTRAINT nota_remision_detalle_pkey;
       public            postgres    false    234            �           2606    17713     nota_remision nota_remision_pkey 
   CONSTRAINT     l   ALTER TABLE ONLY public.nota_remision
    ADD CONSTRAINT nota_remision_pkey PRIMARY KEY (id_nota_remision);
 J   ALTER TABLE ONLY public.nota_remision DROP CONSTRAINT nota_remision_pkey;
       public            postgres    false    232                       2606    20087 >   nota_remision_venta_cabecera nota_remision_venta_cabecera_pkey 
   CONSTRAINT     �   ALTER TABLE ONLY public.nota_remision_venta_cabecera
    ADD CONSTRAINT nota_remision_venta_cabecera_pkey PRIMARY KEY (id_remision);
 h   ALTER TABLE ONLY public.nota_remision_venta_cabecera DROP CONSTRAINT nota_remision_venta_cabecera_pkey;
       public            postgres    false    257                       2606    20100 <   nota_remision_venta_detalle nota_remision_venta_detalle_pkey 
   CONSTRAINT     z   ALTER TABLE ONLY public.nota_remision_venta_detalle
    ADD CONSTRAINT nota_remision_venta_detalle_pkey PRIMARY KEY (id);
 f   ALTER TABLE ONLY public.nota_remision_venta_detalle DROP CONSTRAINT nota_remision_venta_detalle_pkey;
       public            postgres    false    259                       2606    20162 .   notas_credito_debito notas_credito_debito_pkey 
   CONSTRAINT     l   ALTER TABLE ONLY public.notas_credito_debito
    ADD CONSTRAINT notas_credito_debito_pkey PRIMARY KEY (id);
 X   ALTER TABLE ONLY public.notas_credito_debito DROP CONSTRAINT notas_credito_debito_pkey;
       public            postgres    false    261            �           2606    17686    notas notas_pkey 
   CONSTRAINT     S   ALTER TABLE ONLY public.notas
    ADD CONSTRAINT notas_pkey PRIMARY KEY (id_nota);
 :   ALTER TABLE ONLY public.notas DROP CONSTRAINT notas_pkey;
       public            postgres    false    230            '           2606    20458 "   orden_servicio orden_servicio_pkey 
   CONSTRAINT     f   ALTER TABLE ONLY public.orden_servicio
    ADD CONSTRAINT orden_servicio_pkey PRIMARY KEY (id_orden);
 L   ALTER TABLE ONLY public.orden_servicio DROP CONSTRAINT orden_servicio_pkey;
       public            postgres    false    281            �           2606    17539 "   ordenes_compra ordenes_compra_pkey 
   CONSTRAINT     m   ALTER TABLE ONLY public.ordenes_compra
    ADD CONSTRAINT ordenes_compra_pkey PRIMARY KEY (id_orden_compra);
 L   ALTER TABLE ONLY public.ordenes_compra DROP CONSTRAINT ordenes_compra_pkey;
       public            postgres    false    217                       2606    19192    pagos pagos_pkey 
   CONSTRAINT     N   ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_pkey PRIMARY KEY (id);
 :   ALTER TABLE ONLY public.pagos DROP CONSTRAINT pagos_pkey;
       public            postgres    false    253            �           2606    17236    paises paises_pkey 
   CONSTRAINT     U   ALTER TABLE ONLY public.paises
    ADD CONSTRAINT paises_pkey PRIMARY KEY (id_pais);
 <   ALTER TABLE ONLY public.paises DROP CONSTRAINT paises_pkey;
       public            postgres    false    199            !           2606    20399 @   presupuesto_cabecera_servicio presupuesto_cabecera_servicio_pkey 
   CONSTRAINT     �   ALTER TABLE ONLY public.presupuesto_cabecera_servicio
    ADD CONSTRAINT presupuesto_cabecera_servicio_pkey PRIMARY KEY (id_cabecera);
 j   ALTER TABLE ONLY public.presupuesto_cabecera_servicio DROP CONSTRAINT presupuesto_cabecera_servicio_pkey;
       public            postgres    false    275            �           2606    18063 ,   presupuesto_detalle presupuesto_detalle_pkey 
   CONSTRAINT     ~   ALTER TABLE ONLY public.presupuesto_detalle
    ADD CONSTRAINT presupuesto_detalle_pkey PRIMARY KEY (id_presupuesto_detalle);
 V   ALTER TABLE ONLY public.presupuesto_detalle DROP CONSTRAINT presupuesto_detalle_pkey;
       public            postgres    false    210            #           2606    20412 >   presupuesto_detalle_servicio presupuesto_detalle_servicio_pkey 
   CONSTRAINT     �   ALTER TABLE ONLY public.presupuesto_detalle_servicio
    ADD CONSTRAINT presupuesto_detalle_servicio_pkey PRIMARY KEY (id_detalle);
 h   ALTER TABLE ONLY public.presupuesto_detalle_servicio DROP CONSTRAINT presupuesto_detalle_servicio_pkey;
       public            postgres    false    277            �           2606    17350    presupuestos presupuestos_pkey 
   CONSTRAINT     h   ALTER TABLE ONLY public.presupuestos
    ADD CONSTRAINT presupuestos_pkey PRIMARY KEY (id_presupuesto);
 H   ALTER TABLE ONLY public.presupuestos DROP CONSTRAINT presupuestos_pkey;
       public            postgres    false    205            �           2606    17262    producto producto_pkey 
   CONSTRAINT     ]   ALTER TABLE ONLY public.producto
    ADD CONSTRAINT producto_pkey PRIMARY KEY (id_producto);
 @   ALTER TABLE ONLY public.producto DROP CONSTRAINT producto_pkey;
       public            postgres    false    203                       2606    20250    promociones promociones_pkey 
   CONSTRAINT     d   ALTER TABLE ONLY public.promociones
    ADD CONSTRAINT promociones_pkey PRIMARY KEY (id_promocion);
 F   ALTER TABLE ONLY public.promociones DROP CONSTRAINT promociones_pkey;
       public            postgres    false    269            �           2606    17228    proveedores proveedores_pkey 
   CONSTRAINT     d   ALTER TABLE ONLY public.proveedores
    ADD CONSTRAINT proveedores_pkey PRIMARY KEY (id_proveedor);
 F   ALTER TABLE ONLY public.proveedores DROP CONSTRAINT proveedores_pkey;
       public            postgres    false    197                       2606    19065 "   rango_facturas rango_facturas_pkey 
   CONSTRAINT     `   ALTER TABLE ONLY public.rango_facturas
    ADD CONSTRAINT rango_facturas_pkey PRIMARY KEY (id);
 L   ALTER TABLE ONLY public.rango_facturas DROP CONSTRAINT rango_facturas_pkey;
       public            postgres    false    243            %           2606    20440 (   reclamos_clientes reclamos_clientes_pkey 
   CONSTRAINT     n   ALTER TABLE ONLY public.reclamos_clientes
    ADD CONSTRAINT reclamos_clientes_pkey PRIMARY KEY (id_reclamo);
 R   ALTER TABLE ONLY public.reclamos_clientes DROP CONSTRAINT reclamos_clientes_pkey;
       public            postgres    false    279            �           2606    19015 4   recuperacion_contrasena recuperacion_contrasena_pkey 
   CONSTRAINT     r   ALTER TABLE ONLY public.recuperacion_contrasena
    ADD CONSTRAINT recuperacion_contrasena_pkey PRIMARY KEY (id);
 ^   ALTER TABLE ONLY public.recuperacion_contrasena DROP CONSTRAINT recuperacion_contrasena_pkey;
       public            postgres    false    239                       2606    20218 *   servicios_cabecera servicios_cabecera_pkey 
   CONSTRAINT     q   ALTER TABLE ONLY public.servicios_cabecera
    ADD CONSTRAINT servicios_cabecera_pkey PRIMARY KEY (id_cabecera);
 T   ALTER TABLE ONLY public.servicios_cabecera DROP CONSTRAINT servicios_cabecera_pkey;
       public            postgres    false    267                       2606    20319 (   servicios_detalle servicios_detalle_pkey 
   CONSTRAINT     n   ALTER TABLE ONLY public.servicios_detalle
    ADD CONSTRAINT servicios_detalle_pkey PRIMARY KEY (id_detalle);
 R   ALTER TABLE ONLY public.servicios_detalle DROP CONSTRAINT servicios_detalle_pkey;
       public            postgres    false    273                       2606    20210    servicios servicios_pkey 
   CONSTRAINT     V   ALTER TABLE ONLY public.servicios
    ADD CONSTRAINT servicios_pkey PRIMARY KEY (id);
 B   ALTER TABLE ONLY public.servicios DROP CONSTRAINT servicios_pkey;
       public            postgres    false    265            �           2606    19007    usuarios unique_email 
   CONSTRAINT     Q   ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT unique_email UNIQUE (email);
 ?   ALTER TABLE ONLY public.usuarios DROP CONSTRAINT unique_email;
       public            postgres    false    237            �           2606    18977 $   usuarios usuarios_nombre_usuario_key 
   CONSTRAINT     i   ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_nombre_usuario_key UNIQUE (nombre_usuario);
 N   ALTER TABLE ONLY public.usuarios DROP CONSTRAINT usuarios_nombre_usuario_key;
       public            postgres    false    237            �           2606    18975    usuarios usuarios_pkey 
   CONSTRAINT     T   ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);
 @   ALTER TABLE ONLY public.usuarios DROP CONSTRAINT usuarios_pkey;
       public            postgres    false    237                       2606    19100    ventas ventas_pkey 
   CONSTRAINT     P   ALTER TABLE ONLY public.ventas
    ADD CONSTRAINT ventas_pkey PRIMARY KEY (id);
 <   ALTER TABLE ONLY public.ventas DROP CONSTRAINT ventas_pkey;
       public            postgres    false    245            Z           2620    17653 *   detalle_compras trg_insertar_libro_compras    TRIGGER     �   CREATE TRIGGER trg_insertar_libro_compras AFTER INSERT ON public.detalle_compras FOR EACH ROW EXECUTE PROCEDURE public.fn_insertar_libro_compras();
 C   DROP TRIGGER trg_insertar_libro_compras ON public.detalle_compras;
       public          postgres    false    223    283            [           2620    17637 -   detalle_compras trigger_actualizar_inventario    TRIGGER     �   CREATE TRIGGER trigger_actualizar_inventario AFTER INSERT ON public.detalle_compras FOR EACH ROW EXECUTE PROCEDURE public.actualizar_inventario();
 F   DROP TRIGGER trigger_actualizar_inventario ON public.detalle_compras;
       public          postgres    false    223    282            \           2620    19183 )   ventas trigger_generar_cuentas_por_cobrar    TRIGGER     �   CREATE TRIGGER trigger_generar_cuentas_por_cobrar AFTER INSERT ON public.ventas FOR EACH ROW EXECUTE PROCEDURE public.generar_cuentas_por_cobrar();

ALTER TABLE public.ventas DISABLE TRIGGER trigger_generar_cuentas_por_cobrar;
 B   DROP TRIGGER trigger_generar_cuentas_por_cobrar ON public.ventas;
       public          postgres    false    300    245            ]           2620    19143 $   ventas trigger_insertar_libro_ventas    TRIGGER     �   CREATE TRIGGER trigger_insertar_libro_ventas AFTER INSERT ON public.ventas FOR EACH ROW EXECUTE PROCEDURE public.insertar_en_libro_ventas();
 =   DROP TRIGGER trigger_insertar_libro_ventas ON public.ventas;
       public          postgres    false    298    245            8           2606    17670 6   ajustes_inventario ajustes_inventario_id_producto_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.ajustes_inventario
    ADD CONSTRAINT ajustes_inventario_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);
 `   ALTER TABLE ONLY public.ajustes_inventario DROP CONSTRAINT ajustes_inventario_id_producto_fkey;
       public          postgres    false    3027    228    203            @           2606    19044    cajas caja_usuario_fkey    FK CONSTRAINT     y   ALTER TABLE ONLY public.cajas
    ADD CONSTRAINT caja_usuario_fkey FOREIGN KEY (usuario) REFERENCES public.usuarios(id);
 A   ALTER TABLE ONLY public.cajas DROP CONSTRAINT caja_usuario_fkey;
       public          postgres    false    241    3067    237            3           2606    17607 $   compras compras_id_orden_compra_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.compras
    ADD CONSTRAINT compras_id_orden_compra_fkey FOREIGN KEY (id_orden_compra) REFERENCES public.ordenes_compra(id_orden_compra);
 N   ALTER TABLE ONLY public.compras DROP CONSTRAINT compras_id_orden_compra_fkey;
       public          postgres    false    221    217    3043            4           2606    17602 !   compras compras_id_proveedor_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.compras
    ADD CONSTRAINT compras_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.proveedores(id_proveedor);
 K   ALTER TABLE ONLY public.compras DROP CONSTRAINT compras_id_proveedor_fkey;
       public          postgres    false    197    221    3021            5           2606    17620 .   detalle_compras detalle_compras_id_compra_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.detalle_compras
    ADD CONSTRAINT detalle_compras_id_compra_fkey FOREIGN KEY (id_compra) REFERENCES public.compras(id_compra);
 X   ALTER TABLE ONLY public.detalle_compras DROP CONSTRAINT detalle_compras_id_compra_fkey;
       public          postgres    false    223    221    3047            6           2606    17625 0   detalle_compras detalle_compras_id_producto_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.detalle_compras
    ADD CONSTRAINT detalle_compras_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);
 Z   ALTER TABLE ONLY public.detalle_compras DROP CONSTRAINT detalle_compras_id_producto_fkey;
       public          postgres    false    203    223    3027            .           2606    17506 @   detalle_pedido_interno detalle_pedido_interno_numero_pedido_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.detalle_pedido_interno
    ADD CONSTRAINT detalle_pedido_interno_numero_pedido_fkey FOREIGN KEY (numero_pedido) REFERENCES public.cabecera_pedido_interno(numero_pedido) ON DELETE CASCADE;
 j   ALTER TABLE ONLY public.detalle_pedido_interno DROP CONSTRAINT detalle_pedido_interno_numero_pedido_fkey;
       public          postgres    false    213    215    3039            C           2606    19132 ,   detalle_venta detalle_venta_producto_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.detalle_venta
    ADD CONSTRAINT detalle_venta_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.producto(id_producto);
 V   ALTER TABLE ONLY public.detalle_venta DROP CONSTRAINT detalle_venta_producto_id_fkey;
       public          postgres    false    3027    203    247            D           2606    19127 )   detalle_venta detalle_venta_venta_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.detalle_venta
    ADD CONSTRAINT detalle_venta_venta_id_fkey FOREIGN KEY (venta_id) REFERENCES public.ventas(id);
 S   ALTER TABLE ONLY public.detalle_venta DROP CONSTRAINT detalle_venta_venta_id_fkey;
       public          postgres    false    3075    247    245            -           2606    17466 1   entrega_cheques entrega_cheques_id_proveedor_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.entrega_cheques
    ADD CONSTRAINT entrega_cheques_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.proveedores(id_proveedor);
 [   ALTER TABLE ONLY public.entrega_cheques DROP CONSTRAINT entrega_cheques_id_proveedor_fkey;
       public          postgres    false    3021    197    212            K           2606    20163    notas_credito_debito fk_cliente    FK CONSTRAINT     �   ALTER TABLE ONLY public.notas_credito_debito
    ADD CONSTRAINT fk_cliente FOREIGN KEY (cliente_id) REFERENCES public.clientes(id_cliente);
 I   ALTER TABLE ONLY public.notas_credito_debito DROP CONSTRAINT fk_cliente;
       public          postgres    false    261    3033    209            W           2606    20441    reclamos_clientes fk_cliente    FK CONSTRAINT     �   ALTER TABLE ONLY public.reclamos_clientes
    ADD CONSTRAINT fk_cliente FOREIGN KEY (id_cliente) REFERENCES public.clientes(id_cliente) ON UPDATE CASCADE ON DELETE CASCADE;
 F   ALTER TABLE ONLY public.reclamos_clientes DROP CONSTRAINT fk_cliente;
       public          postgres    false    279    209    3033            9           2606    17692    notas fk_compra    FK CONSTRAINT     y   ALTER TABLE ONLY public.notas
    ADD CONSTRAINT fk_compra FOREIGN KEY (id_compra) REFERENCES public.compras(id_compra);
 9   ALTER TABLE ONLY public.notas DROP CONSTRAINT fk_compra;
       public          postgres    false    3047    230    221            ;           2606    17719    nota_remision fk_compra    FK CONSTRAINT     �   ALTER TABLE ONLY public.nota_remision
    ADD CONSTRAINT fk_compra FOREIGN KEY (id_compra) REFERENCES public.compras(id_compra);
 A   ALTER TABLE ONLY public.nota_remision DROP CONSTRAINT fk_compra;
       public          postgres    false    232    3047    221            F           2606    19193    pagos fk_cuenta    FK CONSTRAINT     �   ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT fk_cuenta FOREIGN KEY (cuenta_id) REFERENCES public.cuentas_por_cobrar(id) ON DELETE CASCADE;
 9   ALTER TABLE ONLY public.pagos DROP CONSTRAINT fk_cuenta;
       public          postgres    false    3081    253    251            ?           2606    19021     recuperacion_contrasena fk_email    FK CONSTRAINT     �   ALTER TABLE ONLY public.recuperacion_contrasena
    ADD CONSTRAINT fk_email FOREIGN KEY (email) REFERENCES public.usuarios(email) ON UPDATE CASCADE ON DELETE CASCADE;
 J   ALTER TABLE ONLY public.recuperacion_contrasena DROP CONSTRAINT fk_email;
       public          postgres    false    3063    239    237            M           2606    20184 $   detalle_notas_credito_debito fk_nota    FK CONSTRAINT     �   ALTER TABLE ONLY public.detalle_notas_credito_debito
    ADD CONSTRAINT fk_nota FOREIGN KEY (nota_id) REFERENCES public.notas_credito_debito(id);
 N   ALTER TABLE ONLY public.detalle_notas_credito_debito DROP CONSTRAINT fk_nota;
       public          postgres    false    261    263    3091            =           2606    17745 &   nota_remision_detalle fk_nota_remision    FK CONSTRAINT     �   ALTER TABLE ONLY public.nota_remision_detalle
    ADD CONSTRAINT fk_nota_remision FOREIGN KEY (id_nota_remision) REFERENCES public.nota_remision(id_nota_remision) ON DELETE CASCADE;
 P   ALTER TABLE ONLY public.nota_remision_detalle DROP CONSTRAINT fk_nota_remision;
       public          postgres    false    3059    234    232            1           2606    17584 $   detalle_orden_compra fk_orden_compra    FK CONSTRAINT     �   ALTER TABLE ONLY public.detalle_orden_compra
    ADD CONSTRAINT fk_orden_compra FOREIGN KEY (id_orden_compra) REFERENCES public.ordenes_compra(id_orden_compra);
 N   ALTER TABLE ONLY public.detalle_orden_compra DROP CONSTRAINT fk_orden_compra;
       public          postgres    false    217    219    3043            /           2606    17545    ordenes_compra fk_presupuesto    FK CONSTRAINT     �   ALTER TABLE ONLY public.ordenes_compra
    ADD CONSTRAINT fk_presupuesto FOREIGN KEY (id_presupuesto) REFERENCES public.presupuestos(id_presupuesto);
 G   ALTER TABLE ONLY public.ordenes_compra DROP CONSTRAINT fk_presupuesto;
       public          postgres    false    217    205    3029            2           2606    17589     detalle_orden_compra fk_producto    FK CONSTRAINT     �   ALTER TABLE ONLY public.detalle_orden_compra
    ADD CONSTRAINT fk_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);
 J   ALTER TABLE ONLY public.detalle_orden_compra DROP CONSTRAINT fk_producto;
       public          postgres    false    219    203    3027            >           2606    17750 !   nota_remision_detalle fk_producto    FK CONSTRAINT     �   ALTER TABLE ONLY public.nota_remision_detalle
    ADD CONSTRAINT fk_producto FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);
 K   ALTER TABLE ONLY public.nota_remision_detalle DROP CONSTRAINT fk_producto;
       public          postgres    false    234    203    3027            N           2606    20189 (   detalle_notas_credito_debito fk_producto    FK CONSTRAINT     �   ALTER TABLE ONLY public.detalle_notas_credito_debito
    ADD CONSTRAINT fk_producto FOREIGN KEY (producto_id) REFERENCES public.producto(id_producto);
 R   ALTER TABLE ONLY public.detalle_notas_credito_debito DROP CONSTRAINT fk_producto;
       public          postgres    false    3027    263    203            0           2606    17540    ordenes_compra fk_proveedor    FK CONSTRAINT     �   ALTER TABLE ONLY public.ordenes_compra
    ADD CONSTRAINT fk_proveedor FOREIGN KEY (id_proveedor) REFERENCES public.proveedores(id_proveedor);
 E   ALTER TABLE ONLY public.ordenes_compra DROP CONSTRAINT fk_proveedor;
       public          postgres    false    3021    197    217            :           2606    17687    notas fk_proveedor    FK CONSTRAINT     �   ALTER TABLE ONLY public.notas
    ADD CONSTRAINT fk_proveedor FOREIGN KEY (id_proveedor) REFERENCES public.proveedores(id_proveedor);
 <   ALTER TABLE ONLY public.notas DROP CONSTRAINT fk_proveedor;
       public          postgres    false    197    230    3021            <           2606    17714    nota_remision fk_proveedor    FK CONSTRAINT     �   ALTER TABLE ONLY public.nota_remision
    ADD CONSTRAINT fk_proveedor FOREIGN KEY (id_proveedor) REFERENCES public.proveedores(id_proveedor);
 D   ALTER TABLE ONLY public.nota_remision DROP CONSTRAINT fk_proveedor;
       public          postgres    false    197    232    3021            (           2606    17250 !   proveedores fk_proveedores_ciudad    FK CONSTRAINT     �   ALTER TABLE ONLY public.proveedores
    ADD CONSTRAINT fk_proveedores_ciudad FOREIGN KEY (id_ciudad) REFERENCES public.ciudades(id_ciudad);
 K   ALTER TABLE ONLY public.proveedores DROP CONSTRAINT fk_proveedores_ciudad;
       public          postgres    false    3025    201    197            )           2606    17245    proveedores fk_proveedores_pais    FK CONSTRAINT     �   ALTER TABLE ONLY public.proveedores
    ADD CONSTRAINT fk_proveedores_pais FOREIGN KEY (id_pais) REFERENCES public.paises(id_pais);
 I   ALTER TABLE ONLY public.proveedores DROP CONSTRAINT fk_proveedores_pais;
       public          postgres    false    3023    197    199            X           2606    20459    orden_servicio fk_solicitud    FK CONSTRAINT     �   ALTER TABLE ONLY public.orden_servicio
    ADD CONSTRAINT fk_solicitud FOREIGN KEY (id_solicitud) REFERENCES public.servicios_cabecera(id_cabecera) ON UPDATE CASCADE ON DELETE CASCADE;
 E   ALTER TABLE ONLY public.orden_servicio DROP CONSTRAINT fk_solicitud;
       public          postgres    false    3097    267    281            Y           2606    20464    orden_servicio fk_trabajador    FK CONSTRAINT     �   ALTER TABLE ONLY public.orden_servicio
    ADD CONSTRAINT fk_trabajador FOREIGN KEY (id_trabajador) REFERENCES public.usuarios(id);
 F   ALTER TABLE ONLY public.orden_servicio DROP CONSTRAINT fk_trabajador;
       public          postgres    false    237    3067    281            E           2606    19173    cuentas_por_cobrar fk_venta    FK CONSTRAINT     �   ALTER TABLE ONLY public.cuentas_por_cobrar
    ADD CONSTRAINT fk_venta FOREIGN KEY (venta_id) REFERENCES public.ventas(id) ON DELETE CASCADE;
 E   ALTER TABLE ONLY public.cuentas_por_cobrar DROP CONSTRAINT fk_venta;
       public          postgres    false    3075    251    245            L           2606    20168    notas_credito_debito fk_venta    FK CONSTRAINT     ~   ALTER TABLE ONLY public.notas_credito_debito
    ADD CONSTRAINT fk_venta FOREIGN KEY (venta_id) REFERENCES public.ventas(id);
 G   ALTER TABLE ONLY public.notas_credito_debito DROP CONSTRAINT fk_venta;
       public          postgres    false    245    3075    261            7           2606    17646 *   libro_compras libro_compras_id_compra_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.libro_compras
    ADD CONSTRAINT libro_compras_id_compra_fkey FOREIGN KEY (id_compra) REFERENCES public.compras(id_compra);
 T   ALTER TABLE ONLY public.libro_compras DROP CONSTRAINT libro_compras_id_compra_fkey;
       public          postgres    false    3047    226    221            G           2606    20073 =   nota_remision_cabecera nota_remision_cabecera_cliente_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.nota_remision_cabecera
    ADD CONSTRAINT nota_remision_cabecera_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(id_cliente);
 g   ALTER TABLE ONLY public.nota_remision_cabecera DROP CONSTRAINT nota_remision_cabecera_cliente_id_fkey;
       public          postgres    false    255    3033    209            H           2606    20088 C   nota_remision_venta_cabecera nota_remision_cabecera_cliente_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.nota_remision_venta_cabecera
    ADD CONSTRAINT nota_remision_cabecera_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(id_cliente);
 m   ALTER TABLE ONLY public.nota_remision_venta_cabecera DROP CONSTRAINT nota_remision_cabecera_cliente_id_fkey;
       public          postgres    false    257    209    3033            I           2606    20106 B   nota_remision_venta_detalle nota_remision_detalle_producto_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.nota_remision_venta_detalle
    ADD CONSTRAINT nota_remision_detalle_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.producto(id_producto);
 l   ALTER TABLE ONLY public.nota_remision_venta_detalle DROP CONSTRAINT nota_remision_detalle_producto_id_fkey;
       public          postgres    false    259    3027    203            J           2606    20111 B   nota_remision_venta_detalle nota_remision_detalle_remision_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.nota_remision_venta_detalle
    ADD CONSTRAINT nota_remision_detalle_remision_id_fkey FOREIGN KEY (remision_id) REFERENCES public.nota_remision_venta_cabecera(id_remision) ON DELETE CASCADE;
 l   ALTER TABLE ONLY public.nota_remision_venta_detalle DROP CONSTRAINT nota_remision_detalle_remision_id_fkey;
       public          postgres    false    3087    257    259            S           2606    20400 K   presupuesto_cabecera_servicio presupuesto_cabecera_servicio_id_cliente_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.presupuesto_cabecera_servicio
    ADD CONSTRAINT presupuesto_cabecera_servicio_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.clientes(id_cliente);
 u   ALTER TABLE ONLY public.presupuesto_cabecera_servicio DROP CONSTRAINT presupuesto_cabecera_servicio_id_cliente_fkey;
       public          postgres    false    275    209    3033            +           2606    17445 ;   presupuesto_detalle presupuesto_detalle_id_presupuesto_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.presupuesto_detalle
    ADD CONSTRAINT presupuesto_detalle_id_presupuesto_fkey FOREIGN KEY (id_presupuesto) REFERENCES public.presupuestos(id_presupuesto);
 e   ALTER TABLE ONLY public.presupuesto_detalle DROP CONSTRAINT presupuesto_detalle_id_presupuesto_fkey;
       public          postgres    false    205    3029    210            ,           2606    17450 8   presupuesto_detalle presupuesto_detalle_id_producto_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.presupuesto_detalle
    ADD CONSTRAINT presupuesto_detalle_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.producto(id_producto);
 b   ALTER TABLE ONLY public.presupuesto_detalle DROP CONSTRAINT presupuesto_detalle_id_producto_fkey;
       public          postgres    false    210    3027    203            T           2606    20413 J   presupuesto_detalle_servicio presupuesto_detalle_servicio_id_cabecera_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.presupuesto_detalle_servicio
    ADD CONSTRAINT presupuesto_detalle_servicio_id_cabecera_fkey FOREIGN KEY (id_cabecera) REFERENCES public.presupuesto_cabecera_servicio(id_cabecera);
 t   ALTER TABLE ONLY public.presupuesto_detalle_servicio DROP CONSTRAINT presupuesto_detalle_servicio_id_cabecera_fkey;
       public          postgres    false    277    3105    275            U           2606    20418 K   presupuesto_detalle_servicio presupuesto_detalle_servicio_id_promocion_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.presupuesto_detalle_servicio
    ADD CONSTRAINT presupuesto_detalle_servicio_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.promociones(id_promocion);
 u   ALTER TABLE ONLY public.presupuesto_detalle_servicio DROP CONSTRAINT presupuesto_detalle_servicio_id_promocion_fkey;
       public          postgres    false    3099    269    277            V           2606    20423 J   presupuesto_detalle_servicio presupuesto_detalle_servicio_id_servicio_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.presupuesto_detalle_servicio
    ADD CONSTRAINT presupuesto_detalle_servicio_id_servicio_fkey FOREIGN KEY (id_servicio) REFERENCES public.servicios(id);
 t   ALTER TABLE ONLY public.presupuesto_detalle_servicio DROP CONSTRAINT presupuesto_detalle_servicio_id_servicio_fkey;
       public          postgres    false    265    277    3095            *           2606    17351 +   presupuestos presupuestos_id_proveedor_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.presupuestos
    ADD CONSTRAINT presupuestos_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.proveedores(id_proveedor);
 U   ALTER TABLE ONLY public.presupuestos DROP CONSTRAINT presupuestos_id_proveedor_fkey;
       public          postgres    false    197    3021    205            O           2606    20219 5   servicios_cabecera servicios_cabecera_id_cliente_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.servicios_cabecera
    ADD CONSTRAINT servicios_cabecera_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.clientes(id_cliente);
 _   ALTER TABLE ONLY public.servicios_cabecera DROP CONSTRAINT servicios_cabecera_id_cliente_fkey;
       public          postgres    false    3033    267    209            P           2606    20320 4   servicios_detalle servicios_detalle_id_cabecera_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.servicios_detalle
    ADD CONSTRAINT servicios_detalle_id_cabecera_fkey FOREIGN KEY (id_cabecera) REFERENCES public.servicios_cabecera(id_cabecera);
 ^   ALTER TABLE ONLY public.servicios_detalle DROP CONSTRAINT servicios_detalle_id_cabecera_fkey;
       public          postgres    false    273    267    3097            Q           2606    20330 5   servicios_detalle servicios_detalle_id_promocion_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.servicios_detalle
    ADD CONSTRAINT servicios_detalle_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.promociones(id_promocion);
 _   ALTER TABLE ONLY public.servicios_detalle DROP CONSTRAINT servicios_detalle_id_promocion_fkey;
       public          postgres    false    3099    273    269            R           2606    20325 4   servicios_detalle servicios_detalle_id_servicio_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.servicios_detalle
    ADD CONSTRAINT servicios_detalle_id_servicio_fkey FOREIGN KEY (id_servicio) REFERENCES public.servicios(id);
 ^   ALTER TABLE ONLY public.servicios_detalle DROP CONSTRAINT servicios_detalle_id_servicio_fkey;
       public          postgres    false    265    3095    273            A           2606    19101    ventas ventas_cliente_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.ventas
    ADD CONSTRAINT ventas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(id_cliente);
 G   ALTER TABLE ONLY public.ventas DROP CONSTRAINT ventas_cliente_id_fkey;
       public          postgres    false    245    209    3033            B           2606    27397    ventas ventas_solicitud_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.ventas
    ADD CONSTRAINT ventas_solicitud_id_fkey FOREIGN KEY (solicitud_id) REFERENCES public.servicios_cabecera(id_cabecera);
 I   ALTER TABLE ONLY public.ventas DROP CONSTRAINT ventas_solicitud_id_fkey;
       public          postgres    false    3097    267    245            �   �   x�u�Q�0D�wO�@������S��ڒB����b.TbI��ovf�
����*3I��bw1����IV0��`���@l� Ւ� �?�r�����jNZ懌j���z��oc3z�v�n��N1���;/���׳��H�/6��I���5w��5�v2+��ި�X�TB��ӆh&��}��`�#��Vh�      �   O   x�3�4��M,J�/�tL�L-*��4202�54�52�44�2��22��!S.c<,9����LL�����b���� &��      �   �   x�3���430732���H�KtH�M���K���4202�50"���2�,*���4��042Cbu�p���g���N�KN,JOLɇ�bd�khgr�b7&��L�#.3N�	P����1z\\\ �Q�         �   x���1�!К����`�E��i��iG���H�N��
}?>.��5pu��$3ShP�D����?o�n�z��ԥnfK�b$�� `ז2�fF������J>�0�S��5�����=;�D����(	��v�ycfd��O&�2-��6��F��	Y7L�m������H��oisX��2_�}���1G/iY�_�na      �   >   x�3����ITp��,N�2�t,.�K����2��I�MJ,J�2�N�Sp�+��������� �>�      �   �   x�e�Kn!������a�q�n�m�������>T�^��?���3d�QD�\���T�`��:?xc D�B�OԠQ��|�W���"za���R�΅�`�i�¨����d�Ti%��z9Ӯ�1:>�H�L��&7z�a4l�0
ݡV��]o,��,��B��	���b���Й�B���*��U����篲E���"Tɩ#�����Gw|�C�>Rܤ&�o{߻�(���8ol�      �   �   x����
�0E��I�_ɜ�_�%�](�*
Q

��sb]	��D�C�.���^o�k&f����ba�`3�Z8�٩:��9���;������=��5=����N\Aӥ�vX1���{%�x�η�۠b��0�`�d������򭣊N����w��ų�*ʉ�PN
�(�:Y�'�Z�&���J��{�8�+
�`,��G�ȴ         �   x���1
�0��Y�K�%Yvr���K �tI3���2$�o�?�Q��$I���.�VK1%��my��w��#8��!�pz�μ.N��Dy��ii'�J������)p��T�4C_Z{Z�ҹD�GU����B�J�:C�J����_R��%�]2���d���H���H�o�k��v�@���.�v��uk���4�viΒ�Gh��	����!�ε��      "   %   x�3�LI-NV04P�44�30�LL.�,������ h��      �   L  x�}�K��0DםSp��/�5f=�D�@d5��:#�T����9e/C��*	?�ѹƋgq���(��I��d�Ҳ�Haq'�Չ�BH�VB��R���*-�Ti͢��k�x�S����>HrR��(�TǱ�L���,�~:��Aԡ���9�7��v&R�-ߓ�tK�i�|O��෤�1"-��I�0����q� \�3���S/�i�K�e������|Az�ǙD*
�(X�p���&j�E螩�3@D�X�"�L�&
�"4.T�0Q6��q�!���������8�� �:��~��v�, �Q�7@&��M�<�d         �   x�u���0C��aP���]�&`�9ΔCp�Ey��8���{��1Vs~G�l�T��0�3�5�m0ה���E���Y�5	&MrR�6�A���%�p��q#��?����l����t�a�39n�O��:}��hrD~'��yO��p��Doz<�M�DoM�$Ǧ�h ��Co[RJ_�4�-      �   �   x�}�A�0EןSx338P���MM$J���w
jL�l����A�`���� %8=�����C5����|�7�օ�,+v����F~uL���!��8�w�\�y��|2�Y��-�"��wK0���X��wߏ1�D��K;,k�n�6�s"�2"�~D"��KT}�J��׃w�u��M���>|'��T���X�D�vb      �   v   x�]�;�0�z�� �'^�kP�,��Hũ8}vE�)�if<{Dx4y�*�m/�@�B�ɩF�H8��(�;��Q�"o#�b%F{ɲ��me�?�~�I�
�γS�p�?�;���@D'}^-/      
   "  x�e�Y��0C��b�w{y�_�3Phb��BG&x(�Z��S�����T�M:���@�ȱ�(����W�u�";O�u�;@SF�jGU����^�o��{��x��M6��������z���>�gh��:L�h�&Z´�6`�D�߬^+㵮�\����n��������fcS�9� 4�U��`��9�#4�Bs�#4������EJ���B��F�^9�p\#v}������݆�/�#���I큃���AR#s���$52I��A��� C�������P�m��"4�k      �   9   x�3�4�44 =N##c]CC]NC�Լ�����������☢�<�=...  ��      �   )   x�3��5454502��45�2�446�2�465������ Y_�      �   �   x�m�I� ��_���������g��]t2.)������ɉ��|�.0��#IX`"��$y������6^I�䙂�ƅA�r?��Bj7גm�@�V 1[>k~-y���� fˇ�UA����tۺ~��Z|s�46n�M���.��P>B�;�BxU�=d>:mB&���)���y
�{(!ϗ](�|�|�Y���w)0�n���F�TP��\�0�v�d9������s�����         �  x���]�9���S�#�G$%bO���dǋ�7�ߒ,��;i@��(�(Nf��R�����r�~KBR�Xޘ�����~�~M_�H��߿^����X���TT���$�O�䝮�_õA<�
Ӧ�&�ey�N�^��ے&:�m���h�dm����s�d�I�t;�y�mfɣmmX/����HN��ɫ�=pUyi��<�����)���V��j��e	�W0�	�R���4��'�A���d��8L��ʅ8�I��и�b�1p���ᨔ��g���nx�����Ზ|m5u~�����u��2��8�����f���Q1g5��R��g�x�g�Ea��=���
6� B���P�B)����G��6���)��h��m^�bj�	�cERت�y��^�Kˢ)�鯀���+7l��"Vn�q��>o��?���>>?h#Q�T檚���>*�A.p3Fʼ���������^E�!���7SAw�LgF��:��Pw��l�(���:հ}<hґ
�ҳN1��TK�/����r��X�S��\ru�R�. �:ň'��������.�c�i�mq�m<�Hc��K��S����������¬�W�ƛK��|�1y�y� 2�E�{�V�B��"��x�B�uvj��"?��/ 
�3��A^YdoS&�*u�')��"yHi,�P%˸$������"A�FS��9V<}��[cS��ֵ�/%���L�      �   ]   x�3�4�4202�50"NS ��1�4'1%�˘�Y�,�\�Y��e�i���54�44�42��a�5Ҕ���� Y����$m�S:F��� �3$1            x������ � �      �   �   x���K
� E��Ud��^:1Th��и�4d�)���C ��/~���0r���UL�4r�1z*�,uY���0�d5i�;4�~�0lv-�����wg����}�$��0�h����OZ��!��9@W$O�Yo��)�Le�e�g��]��X6:9���Z��(��0�p�         �   x�]�1�0@�99��'�}�.�d�D��޿AB*�������(�H#�@d(�B$���ޗzL��D<;Ɵ.6],fȒ��]'��ݴ�MJ�o�]��H j�u�ҷ�>g �FLnZ?�.wÀ�8�P
%���:��z�?�{���>          P   x�]�� !D��P�aQ������Db����`��p��T��0�<��%[r6Mx�V��ӋQ��f%&݇|�jfIw�5�)\�      �   �   x���Q� ���)v��҉�Go�|�1dF��v~;�Ψ	!)����`l�z�:G�4(P�+D�w��+�5��("Ns�n�~N��"/�|ɥL|m��&���\n�JG��,�nt����]�]�l��x)����i��oRC�YsO���9��a>Jc��e��~���J=~�jCk*�<�y���y��2{��6E�B\g~��         3  x���Mn�0���)|�
�(i;�9A7i셁 	2m��~5���@���#�����[�a��9(oނ� ���SH����0����I����_��ʽ��ץ6�R	�kHʿs � �"�sJ����-P,��g���Vԓ�RQ�F!f�R \ ��TI�M�XX|"M(q�*JPjσ��Rz鯹�X�'>B��P��񏮼c�* ��e t�ah�X�����*�=lZ�@�A�5�EP��"��Ϡ��Z�YЂ�Ĭ)��t�q�GP�86ݤŞ�r�g��VvQ�4�Q����*��/���� @/��aȷ���|��4�Q, Л�����"����¡�Y�pvM7H�4�h�I`���z�4L��-���
�A�RgB� �S;s|�,鋒y�i��=�|�`��,7���f�5���h]������ŭ��i�V�ma�]�-D�D�g &�f�0~���\���U��*��x8N�i����t��rP�-��G��#����h[��Z$F;��b�R����K�}X.�`����1�X��-�J~NU��`��^����w]�zq�	      ,   �   x�mϻqa�XW�5�F�_R���c;���� �s}�+#P!��sjͶDVS���������}��Ǧ`�z/���rka-.����-д�f�����*.6:L
p~��#~5F<;X�X9@����̢�\���	b>]�6A5YK"-�����M���f͌R�&8�mw� d�      �   �   x����n� �继�R�3�c��:g��^�r�ҧ�!E�����oY�}?��:2�N�ʑQ�r��)��x[RT��$������@�#�3vVw0ǐ2p�����_������.4`���UY*���l�������̈��n�:���<�4��@�������T�ĩ27��G̲7h2��濭�A��~K��@�s�Z����Li�u�S��E��lP�-�>}��2�x}C�;��ͺ         �   x���;n�0К���H�t��9@�E~H�M��g�.�a���|А��"C"������G�>�_��~�|���=�J�S
61�`��k�bAAth��&V9���h�qr6�I49���z
U
Νp�]ܨ+��3��m�8��NIT�����j�:����^G�)q��*�&����c����{:�o���Iga�����0Y�X�Y8HXt�z����~����|$���/�,�o�k      �   L   x�3�H,JL/M��,�2��+��8���3s�TjQ>�1�cQzj^If^"���e�锟�Y��������b���� Ț�      &   G   x�3�4��4202�50�54�,H�K�L�+I�4�30�0  �ː��Y]QjrFbUbJ>D��)T]� �      �   �  x�mR[r�0�6�阗�ܥ�?G����np$�SjC���9�2�@㯆�G��z�6�',�W�A�'���(8����� u�!�̻�"݅�u������\~Y}��)HY����"%�d-�j��x��׋��92B�"d~����Sɸrt�ƍL>�N��%.��,5�wFd�>d0���0���R� 2L�#y�β�dh����:w]� ��JMn�R��ch+��U��h�ѱG)�ӑ�\�K������ȭR�#6�WIR*�u�W���k�Z���|׎���G�ԒSb��+u���������*��v��@(�Ji�\�:-���2��<z�J$�n�X���¡eE�[�>`�Xo�-7-���xH��p�:��/"�C=�b      (   .   x�3�4�?NcS= �ˈ�S�(��@Źb���� ���      �   w  x����n�0Eg�_\�=<�:wI@�����Ծ��D�:�$E�L%p��:F���LW�����v�8������+TG*�) i:8�M������u�]�%VP*A�JmH�B^d�8�I�/�F�*�X'�j�����Q�=��ٵ��@����lV��Z��J�*˭R�	MMk��U��P��@�ߡ(1f���]������@{�77��,��oPS%J;�dW��SFhr^9�ѝ)�Z��ed9����3�ϲ��f��R:�)�Hz ?a��� �%5}y�;/ά�ã`����5|1ٙ苨r2�f)�aت�Zܗ��Ss��B~���5ۘ�M��}���L�Uz}��^�P      �   �   x��QAN�0<�_�Tv�K%N�p��˦Y���b����$$�� Y+ffgf�H�T7�(��Zx;��Sg����3��T�d����p�D%E�4-����S��H�j���[��5���+�e�ܠ�fw���8���:�#���X�)p�J۩�b����s�f_��&��x�D@�NШN��%=�K g��P�.b�Y����#J�xR���pw%w�c>����          8   x�3�L�/*IU�M,N.����W�V�I,KL��41500�30�LL.�,������ w��      �   [  x�]��n� E��@��b�5M��&��������R,���}ǏFr<Y����"\]k�_��U��-�*]q��ޮ%�"�C	���s�%P�=x�`� ئ�mQ #׉����S<�C��m�PaX���U4�Q��C\"HI�3 ��v��F� E��>7�� o��`�-K�JR	!�*Z��H�/G�d�����P���ƳQJ��j?x��Yg� i:�� ���.��Nt2J�2*�g܋�/.�m����(��i����5z�
��[v�71���>;�2�N��m7�=�f�Ϗ��5�.�X%�U�'����X�������j_�nɨ�a�C�'����a�         T   x�3�440�45 S��FF&��@�```F 1St�4.#d��$�4j1�jj74G�3G�k�@��p"�jbI��1z\\\ 8�)6      *   i   x�U�A�  �s�
> C0A�-�`́��o/z���v�̦��#��y4
�8�l��4�n�{��,���w�-��)�E�8
�G�lYKW��E�/
 '         W   x���	�0�s;�T�߆jO�%�(�E����e
���35�mW�����A	dET�}�zT:�p峸��JbN,�
�9��wT�         a   x�e�A
� @���)<��Y'�m�4Pc��B-���|���*��
���HAe����'Hmg��_��o�Z���-F������1;�nb�-\4"�l�(�         �   x�����0�s�.��k���3zAC���;D&����_��K'�F�� ���ڻ�X"B�ᄋ�;��m�$IR�ݓ��y���\���77�v�cy��/��pL���^}�U�U���X]/!c�8�!H���0l�A��qu~��>�'�V�6��]Jc��#�6      $   �   x�m��� �K1�ې&���_�y����%�h��v����`��\"��t<'�;i:���ZcCtr����3�I�xG��7��"&`���e[L�{��Ŕwa+q�-~ۉ�����&��+6�B�l�b�>����O�D�V�܎)���8��/����Z���n�          �  x�}�Io�0��=p��'9�Ua+�S@�FY�F���'�p�E��'?�����釛��N�:Fuw�z�BPgx�;
z�9�Z{��)��/����V��aX�K�]��� ^' ��1��k`�@�	k&&�P1t����bwA?�2tL����!�d��?�`� {LV� q��d�F�u
�Y���(�Yy�qn��V�6=�	�V^�;�H��l����Y��B�����Y����M�C�2]�G��"w�]�ރ�0$!�	�1��W vs?-��g���a����`jg��Ɋf��]�ߜ���[:���V��\����Yۊ��7{��D��2C�9Ԋ��]_沸O�B!����:Ǿ�Pc�
��J%����^znrc�u්f���N�^����PM���B�DKQE��h/�!z.-pL���]_����r.~<���7��"��I4)	8ǐ ����%��k��_��         �  x���mj1���Sx�����n��GtB�Bm���Zׄf6�1L�7�h�h��H=� ~���|�/�c:O��:�ݫ�`��o��}ίn�)XWF�BuA�X����q�0��H��6����A��Ă���ب6��j���.��g�8�cq�4�+��O�d�r*ԘJ��=?k���Q��uD� L��A��r���Z.�2˕P Bf�9ZIR룎r˥�0Qȭ/��6#$7�ɍ-F�n@#�7��Z��_.G>�&#$���3c�����{Ș�Ϥ�Kiĸ0�_�bc۟���g��A�.7csQk�4?kh�U���N?�~�IdT����cV�C�&>�#
����eY��х�]峛X\�\>�66�b������XPa�XTm b�0cC����t�����;ʓ�P{�,�@������ ����*mF:)4#����2��e
I�uw_�n�u��2j     