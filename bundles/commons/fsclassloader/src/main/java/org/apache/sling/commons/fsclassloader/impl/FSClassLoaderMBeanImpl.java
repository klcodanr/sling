/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package org.apache.sling.commons.fsclassloader.impl;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.apache.sling.commons.fsclassloader.FSClassLoaderMBean;
import org.osgi.framework.BundleContext;

/**
 * Implementation of the FSClassLoaderMBean interface
 */
public class FSClassLoaderMBeanImpl implements FSClassLoaderMBean {
	private final BundleContext context;
	private final FSClassLoaderProvider fsClassLoaderProvider;

	public FSClassLoaderMBeanImpl(final FSClassLoaderProvider fsClassLoaderProvider, final BundleContext context) {
		this.fsClassLoaderProvider = fsClassLoaderProvider;
		this.context = context;
	}

	/*
	 * (non-Javadoc)
	 * 
	 * @see org.apache.sling.commons.fsclassloader.FSClassLoaderMBean#
	 * cachedScriptCount()
	 */
	@Override
	public int cachedScriptCount() throws IOException {
		Map<String, ScriptFiles> scripts = new LinkedHashMap<String, ScriptFiles>();
		FSClassLoaderWebConsole.readFiles(new File(context.getDataFile(""), "classes"), scripts);
		return scripts.keySet().size();
	}

	/*
	 * (non-Javadoc)
	 * 
	 * @see
	 * org.apache.sling.commons.fsclassloader.FSClassLoaderMBean#cachedScripts()
	 */
	@Override
	public List<String> cachedScripts() throws IOException {
		Map<String, ScriptFiles> scripts = new LinkedHashMap<String, ScriptFiles>();
		FSClassLoaderWebConsole.readFiles(new File(context.getDataFile(""), "classes"), scripts);
		List<String> s = new ArrayList<String>();
		s.addAll(scripts.keySet());
		Collections.sort(s);
		return s;
	}

	/*
	 * (non-Javadoc)
	 * 
	 * @see
	 * org.apache.sling.commons.fsclassloader.FSClassLoaderMBean#clearCache()
	 */
	@Override
	public void clearCache() {
		fsClassLoaderProvider.delete("");
	}

	/*
	 * (non-Javadoc)
	 * 
	 * @see org.apache.sling.commons.fsclassloader.FSClassLoaderMBean#
	 * fsClassLoaderRoot()
	 */
	@Override
	public String fsClassLoaderRoot() {
		return new File(context.getDataFile(""), "classes").getAbsolutePath();
	}

}
