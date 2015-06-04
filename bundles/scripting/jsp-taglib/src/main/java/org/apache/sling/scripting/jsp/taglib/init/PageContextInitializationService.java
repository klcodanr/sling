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
package org.apache.sling.scripting.jsp.taglib.init;

import javax.servlet.jsp.PageContext;

import org.apache.sling.api.resource.Resource;
import org.apache.sling.api.resource.ResourceResolver;

/**
 * OSGi Service for initializing the page context based on the resource type and
 * a naming convention.
 */
public interface PageContextInitializationService {

	/**
	 * 
	 * Initializes the page context using the specified resource. Uses the rules
	 * defined in getClassName to determine the class name to initialize the
	 * page context, searching up the resource super type hierarchy.
	 * 
	 * 
	 * @param context
	 *            the page context for the current request
	 * @param resource
	 *            the current resource
	 */
	void initialize(PageContext pageContext, Resource resource);

	/**
	 * Gets the class name for the initialization class based the specified
	 * resource. The convention used:
	 * {PREFIX}.{RESOURCE_TYPE}.{RESOURCE_TYPE_NAME}. Dashes will be replaced
	 * with underscores, java keywords will be be appended with an underscore
	 * and segments beginning with numeric values will be prefixed with an
	 * underscore.
	 * 
	 * For example:
	 * <ul>
	 * <li>Resource Type: my-component/3_rd_iteration/int</li>
	 * <li>Prefix: com.mycompany</li>
	 * <li>Binding Class: com.mycompany.my_component._3_rd_iteration.Int_</li>
	 * </ul>
	 * 
	 * @param resolver
	 *            the resource resolver
	 * @param resourceType
	 *            the resource type string
	 * @return the name of the class corresponding for the specified resource
	 *         type
	 */
	String getClassName(ResourceResolver resolver, String resourceType);
}
