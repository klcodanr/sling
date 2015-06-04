/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.sling.scripting.jsp.taglib.init.impl;

import javax.servlet.jsp.PageContext;

import org.apache.commons.lang.StringUtils;
import org.apache.commons.lang.WordUtils;
import org.apache.felix.scr.annotations.Component;
import org.apache.felix.scr.annotations.Property;
import org.apache.felix.scr.annotations.Service;
import org.apache.sling.api.resource.Resource;
import org.apache.sling.api.resource.ResourceResolver;
import org.apache.sling.commons.osgi.PropertiesUtil;
import org.apache.sling.scripting.jsp.taglib.init.PageContextInitializationService;
import org.apache.sling.scripting.jsp.taglib.init.PageContextInitializer;
import org.osgi.service.component.ComponentContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Implementation of the PageContextInitializationService
 */
@Service
@Component(metatype = true, immediate=true)
public class PageContextInitializationServiceImpl implements
		PageContextInitializationService {

	/**
	 * The default package prefix
	 */
	private static final String DEFAULT_PACKAGE_PREFIX = "org.apache.sling.init";

	/**
	 * All of the reserved java words which need to be escaped
	 */
	private static final String[] JAVA_RESERVED = new String[] { "abstract",
			"do", "if", "package", "synchronized", "boolean", "double",
			"implements", "private", "this", "break", "else", "import",
			"protected", "throw", "byte", "extends", "instanceof", "public",
			"throws", "case", "false", "int", "return", "transient", "catch",
			"final", "interface", "short", "true", "char", "finally", "long",
			"static", "try", "class", "float", "native", "strictfp", "void",
			"const", "for", "new", "super", "volatile", "continue", "goto",
			"null", "switch", "while", "default", "assert" };

	private static final Logger log = LoggerFactory
			.getLogger(PageContextInitializationServiceImpl.class);

	/**
	 * Constant for the package prefix property
	 */
	@Property(label = "Package Prefix", value = DEFAULT_PACKAGE_PREFIX)
	private static final String PACKAGE_PREFIX = "package.prefix";

	private String packagePrefix = DEFAULT_PACKAGE_PREFIX;

	/**
	 * Called when this OSGi Service is activated
	 * 
	 * @param context
	 *            the OSGi context for the service
	 */
	protected void activate(ComponentContext context) {
		packagePrefix = PropertiesUtil.toString(
				context.getProperties().get(PACKAGE_PREFIX),
				DEFAULT_PACKAGE_PREFIX);
	}

	/*
	 * (non-Javadoc)
	 * 
	 * @see
	 * org.apache.sling.scripting.jsp.taglib.init.PageContextInitializationService
	 * #getClassName(org.apache.sling.api.resource.ResourceResolver,
	 * java.lang.String)
	 */
	public String getClassName(ResourceResolver resolver, String resourceType) {
		log.trace("Getting class name for {}", resourceType);
		String className = null;
		if (!StringUtils.isEmpty(resourceType)) {
			StringBuffer buf = new StringBuffer(packagePrefix + ".");
			for (String searchPathItem : resolver.getSearchPath()) {
				if (resourceType.startsWith(searchPathItem)) {
					resourceType = resourceType.substring(searchPathItem
							.length());
					break;
				}
			}
			String[] resourceTypeSegments = resourceType.split("\\/");
			for (int i = 0; i < resourceTypeSegments.length; i++) {
				String resourceTypeSegment = resourceTypeSegments[i];
				if ((i + 1) < resourceTypeSegments.length) {
					buf.append(javaEncode(resourceTypeSegment, false));
					buf.append(".");
				} else {
					buf.append(javaEncode(resourceTypeSegment, true));
				}
			}
			className = buf.toString();
		}
		return className;
	}

	/*
	 * (non-Javadoc)
	 * 
	 * @see
	 * org.apache.sling.scripting.jsp.taglib.init.PageContextInitializationService
	 * #initialize(javax.servlet.jsp.PageContext,
	 * org.apache.sling.api.resource.Resource)
	 */
	public void initialize(PageContext context, Resource resource) {
		initialize(context, resource.getResourceType(),
				resource.getResourceResolver());
	}

	private void initialize(PageContext context, String resourceType,
			ResourceResolver resolver) {
		if (!StringUtils.isEmpty(resourceType)) {
			String parentResourceType = resolver
					.getParentResourceType(resourceType);
			if (!resourceType.equals(parentResourceType)) {
				initialize(context, parentResourceType, resolver);
			}
			runInitializer(getClassName(resolver, resourceType), context);
		}
	}

	private String javaEncode(String str, boolean capitalize) {
		log.trace("Java encoding {}", str);
		StringBuffer buf = new StringBuffer();
		boolean checkReserved = true;
		if (Character.isDigit(str.charAt(0))) {
			buf.append("_");
			checkReserved = false;
		}
		if (str.contains("-")) {
			str = str.replace("-", "_");
			checkReserved = false;
		}
		if (capitalize) {
			buf.append(WordUtils.capitalize(str));
		} else {
			buf.append(str);
		}
		if (checkReserved) {
			for (String reserved : JAVA_RESERVED) {
				if (reserved.equals(str)) {
					buf.append("_");
					break;
				}
			}
		}
		return buf.toString();
	}

	private void runInitializer(String className, PageContext context) {
		log.trace("Loading initializer for {}", className);
		if (!StringUtils.isEmpty(className)) {
			try {
				Class<?> clazz = getClass().getClassLoader().loadClass(
						className);
				if (PageContextInitializer.class.isAssignableFrom(clazz)) {
					log.trace("Loading initializer {}",
							clazz.getCanonicalName());
					PageContextInitializer initializer = (PageContextInitializer) clazz
							.newInstance();
					initializer.intitialize(context);
				}
			} catch (ClassNotFoundException cnfe) {
				// ignore
			} catch (InstantiationException e) {
				log.error("Exception instantiating initializer for "
						+ className, e);
			} catch (IllegalAccessException e) {
				log.error("Illegal access instantiating initializer for "
						+ className, e);
			}
		}
	}
}
